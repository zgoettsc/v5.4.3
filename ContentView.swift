import SwiftUI
import TelemetryDeck
import UserNotifications
import AVFoundation
import AudioToolbox
import FirebaseAuth
import FirebaseDatabase

struct TimeOfDayTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(10)
    }
}

extension Category {
    var icon: String {
        switch self {
        case .medicine: return "pills.fill"
        case .maintenance: return "applelogo"
        case .treatment: return "fork.knife"
        case .recommended: return "star.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .medicine: return .blue
        case .maintenance: return .green
        case .treatment: return .purple
        case .recommended: return .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .medicine, .maintenance, .treatment, .recommended:
            return Color(.secondarySystemBackground)
        }
    }

    var progressBarColor: Color {
        switch self {
        case .treatment: return .purple
        case .recommended: return .orange
        default: return .blue
        }
    }
}

struct ScrollViewOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ProfileHeaderView: View {
    let appData: AppData
    let name: String
    let cycle: Int
    let week: Int
    let day: Int
    let image: Image?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let cycleId = appData.currentCycleId(),
                   let profileImage = appData.loadProfileImage(forCycleId: cycleId) {
                    Image(uiImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else if let image = image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.secondary)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Cycle \(cycle) • Week \(week) • Day \(day)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }
}

extension View {
    func cardStyle(background: Color = Color(.secondarySystemBackground)) -> some View {
        self
            .padding()
            .background(background)
            .cornerRadius(20)
            .shadow(color: Color.primary.opacity(0.05), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
    }

    func timeOfDayTagStyle(color: Color) -> some View {
        self
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(10)
    }
}
struct NotificationHelper {
    static func playSystemSound() {
        // Just play a simple system sound, no background audio
        AudioServicesPlaySystemSound(SystemSoundID(1005))
    }
}

struct GroupView: View {
    @ObservedObject var appData: AppData
    let group: GroupedItem
    let cycleId: UUID
    let items: [Item]
    let weeklyCounts: [UUID: Int]
    @Binding var forceRefreshID: UUID

    init(appData: AppData, group: GroupedItem, cycleId: UUID, items: [Item], weeklyCounts: [UUID: Int], forceRefreshID: Binding<UUID>) {
        self.appData = appData
        self.group = group
        self.cycleId = cycleId
        self.items = items
        self.weeklyCounts = weeklyCounts
        self._forceRefreshID = forceRefreshID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: {
                    // print("Group \(group.id) button tapped, isChecked=\(isGroupChecked())")
                    toggleGroupCheck()
                    forceRefreshID = UUID()
                }) {
                    Image(systemName: isGroupChecked() ? "checkmark.square.fill" : "square")
                        .foregroundColor(isGroupChecked() ? .secondary : .blue)
                        .font(.title3)
                }
                Text(group.name)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.primary)
                    .onTapGesture {
                        let currentState = appData.groupCollapsed[group.id] ?? true
                        appData.setGroupCollapsed(group.id, isCollapsed: !currentState)
                        // print("Tapped \(group.name), set isCollapsed to \(!currentState)")
                    }
                Spacer()
            }
            if !(appData.groupCollapsed[group.id] ?? true) {
                ForEach(items.filter { group.itemIds.contains($0.id) }, id: \.id) { item in
                    if group.category == .recommended {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Spacer().frame(width: 40)
                                Button(action: {
                                    // print("Item \(item.id) button tapped, isChecked=\(isItemChecked(item: item))")
                                    toggleItemCheck(item: item)
                                    forceRefreshID = UUID()
                                }) {
                                    Image(systemName: isItemChecked(item: item) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isItemChecked(item: item) ? .secondary : .blue)
                                        .font(.title3)
                                }
                                .disabled(isGroupChecked())
                                
                                Text(itemDisplayText(item: item))
                                    .font(.body)
                                    .foregroundColor((weeklyCounts[item.id] ?? 0) >= 3 ? .green : .primary)  // Green text when complete at 3
                                    .padding(.leading, 8)
                                Spacer()
                            }
                            HStack {
                                Spacer().frame(width: 48)
                                // For grouped recommended items: always use /5 display, complete at 3
                                ProgressView(value: min(Double(weeklyCounts[item.id] ?? 0) / 5.0, 1.0))
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .tint((weeklyCounts[item.id] ?? 0) >= 3 ? .green : group.category.progressBarColor)
                                    .frame(height: 5)
                            }
                            HStack {
                                Spacer().frame(width: 48)
                                Text("\(weeklyCounts[item.id] ?? 0)/5 this week")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Spacer().frame(width: 40)
                            Button(action: {
                                // print("Item \(item.id) button tapped, isChecked=\(isItemChecked(item: item))")
                                toggleItemCheck(item: item)
                                forceRefreshID = UUID()
                            }) {
                                Image(systemName: isItemChecked(item: item) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isItemChecked(item: item) ? .secondary : .blue)
                                    .font(.title3)
                            }
                            .disabled(isGroupChecked())
                            Text(itemDisplayText(item: item))
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.leading, 8)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(isGroupChecked() ? Color.secondary.opacity(0.2) : group.category.backgroundColor)
        .cornerRadius(10)
        .onAppear {
            // print("GroupView \(group.name) appeared, weeklyCounts: \(weeklyCounts)")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DataRefreshed"))) { _ in
            self.forceRefreshID = UUID()
        }
    }

    private func isGroupChecked() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return items.filter { group.itemIds.contains($0.id) }.allSatisfy { item in
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
    }

    private func isItemChecked(item: Item) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
        return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    private func itemDisplayText(item: Item) -> String {
        appData.itemDisplayText(item: item)
    }

    private func toggleGroupCheck() {
        let today = Calendar.current.startOfDay(for: Date())
        let isChecked = isGroupChecked()
        if isChecked {
            for item in items.filter({ group.itemIds.contains($0.id) }) {
                if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                    appData.removeConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
                }
            }
        } else {
            for item in items.filter({ group.itemIds.contains($0.id) }) {
                if !isItemChecked(item: item) {
                    appData.logConsumption(itemId: item.id, cycleId: cycleId, date: Date())
                }
            }
        }
    }

    private func toggleItemCheck(item: Item) {
        let today = Calendar.current.startOfDay(for: Date())
        let isChecked = isItemChecked(item: item)
        if isChecked {
            if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                appData.removeConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
            }
        } else {
            appData.logConsumption(itemId: item.id, cycleId: cycleId, date: Date())
        }
    }

    private func currentWeekNumber() -> Int {
        guard let cycle = appData.cycles.first(where: { $0.id == cycleId }) else { return 1 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        return (daysSinceStart / 7) + 1
    }
}

struct RefreshableScrollView<Content: View>: View {
    @State private var previousScrollOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var frozen: Bool = false
    @State private var rotation: Angle = .degrees(0)
    
    var threshold: CGFloat = 80
    let onRefresh: (@escaping () -> Void) -> Void
    let content: Content

    init(onRefresh: @escaping (@escaping () -> Void) -> Void, @ViewBuilder content: () -> Content) {
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { outerGeometry in
            ScrollView {
                ZStack(alignment: .top) {
                    MovingView()
                    
                    VStack {
                        self.content
                            .alignmentGuide(.top, computeValue: { d in
                                (self.scrollOffset >= self.threshold && self.frozen) ? -self.threshold : 0
                            })
                    }
                    
                    SymbolView(height: self.threshold, loading: self.frozen, rotation: self.rotation)
                        .offset(y: min(self.scrollOffset, 0))
                }
                .background(FixedView(scrollOffset: $scrollOffset))
            }
            .onChange(of: scrollOffset) { newValue in
                if !self.frozen && self.previousScrollOffset > self.threshold && self.scrollOffset <= self.threshold {
                    self.frozen = true
                    self.rotation = .degrees(0)
                    
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: 0.3)) {
                            self.rotation = .degrees(720)
                        }
                        self.onRefresh {
                            withAnimation {
                                self.frozen = false
                            }
                        }
                    }
                }
                
                self.previousScrollOffset = self.scrollOffset
            }
        }
    }
    
    struct FixedView: View {
        @Binding var scrollOffset: CGFloat
        
        var body: some View {
            GeometryReader { geometry in
                Color.clear.preference(key: OffsetPreferenceKey.self, value: geometry.frame(in: .global).minY)
                    .onPreferenceChange(OffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
            }
        }
    }
    
    struct MovingView: View {
        var body: some View {
            GeometryReader { geometry in
                Color.clear
            }
        }
    }
    
    struct SymbolView: View {
        var height: CGFloat
        var loading: Bool
        var rotation: Angle
        
        var body: some View {
            Group {
                if loading {
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: height * 0.25, height: height * 0.25)
                            .rotationEffect(rotation)
                            .foregroundColor(.secondary)
                        Spacer()
                    }.frame(height: height)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: height * 0.25, height: height * 0.25)
                            .foregroundColor(.secondary)
                        Spacer()
                    }.frame(height: height)
                }
            }
        }
    }
}

struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect() // Changed from 1 to 2 seconds
    @State private var treatmentCountdowns: [String: TimeInterval] = [:] // Keyed by roomId
    @State private var notificationPermissionDenied = false
    @State private var showingSyncError = false
    @State private var treatmentTimerId: String?
    @State private var forceRefreshID = UUID()
    @State private var showingTimerAlert = false
    @State private var recommendedWeeklyCounts: [UUID: Int] = [:]
    @State private var isRefreshing = false
    @State private var isLoggedIn: Bool = UserDefaults.standard.string(forKey: "currentUserId") != nil
    @State private var showingPrivacyStatement = !UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")
    @State private var showingCycleExpiredAlert = false
    @State private var showingFirstCyclePopup = UserDefaults.standard.bool(forKey: "showFirstCyclePopup")
    @State private var newCycle: Cycle?
    @State private var showingCycleCompletionPopup = false
    @State private var selectedTab = 2 // This will select the Home tab (index 2)
    @State private var settingsNavigationId = UUID()
    @State private var showingSubscriptionManagement = false
    @State private var isRequestingOwnership = false
    @State private var showingOwnershipUpgradeAlert = false
    @State private var showingOwnershipSuccessAlert = false
    @State private var ownershipErrorMessage: String?
    @State private var showingOwnershipErrorAlert = false
    
    init(appData: AppData) {
        self.appData = appData
    }
    
    var body: some View {
        ZStack {
            if showingPrivacyStatement {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                    .zIndex(10)
                
                PrivacyStatementView(isPresented: $showingPrivacyStatement)
                    .zIndex(11)
            }
            
            mainAppContentView()
            
            if showingFirstCyclePopup, let cycle = newCycle {
                FirstCyclePopupView(appData: appData, isPresented: $showingFirstCyclePopup, cycle: cycle, onDismiss: dismissFirstCyclePopup)
                    .zIndex(12)
            }
            if showingCycleCompletionPopup, let currentCycle = appData.cycles.last {
                CycleCompletionPopupView(
                    appData: appData,
                    isPresented: $showingCycleCompletionPopup,
                    previousCycle: currentCycle
                )
                .zIndex(12)
            }
        }
        .onAppear {
            if authViewModel.authState == .signedIn && authViewModel.currentUser != nil && appData.currentUser == nil {
              //  // print("User is signed in but app state doesn't reflect it. Show RoomsSelectionView.")
                DispatchQueue.main.async {
                    appData.currentUser = nil
                    appData.currentRoomId = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDidSignOut"))) { _ in
            authViewModel.signOut()
        }
        .sheet(isPresented: $showingSubscriptionManagement) {
            NavigationView {
                SubscriptionManagementView(appData: appData)
                    .navigationBarItems(trailing: Button("Done") {
                        showingSubscriptionManagement = false
                    })
            }
        }
        .alert("Cycle Completed", isPresented: $showingCycleExpiredAlert) {
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text("Your current cycle has reached its Food Challenge date. You can create a new cycle from Settings.")
        }
    }
    
    private func mainContentView() -> some View {
        VStack {
            headerView()
            if appData.isLoading {
                ProgressView("Loading data from server...")
                    .padding()
            } else if appData.cycles.isEmpty && appData.roomCode != nil && appData.syncError == nil {
                ProgressView("Loading your plan...")
                    .padding()
            } else {
                categoriesScrollView()
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarHidden(true)
        .alert(isPresented: $showingSyncError) {
            Alert(
                title: Text("Sync Error"),
                message: Text(appData.syncError ?? "Unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showingTimerAlert) {
            let roomName = appData.activeTimers.first?.value.roomName ?? "unknown room"
            return Alert(
                title: Text("Time for next treatment food"),
                message: Text("The timer for \(roomName) has ended."),
                primaryButton: .default(Text("Go to Room")) {
                    if let (roomId, _) = appData.activeTimers.first {
                        appData.stopTreatmentTimer(clearRoom: true, roomId: roomId)
                        appData.switchToRoom(roomId: roomId)
                    }
                },
                secondaryButton: .default(Text("Snooze (5 min)")) {
                    if let (roomId, _) = appData.activeTimers.first {
                        appData.snoozeTreatmentTimer(duration: 300, roomId: roomId)
                    }
                }
            )
        }
        .onAppear {
            updateRecommendedItemCounts()
            checkForExpiredCycle()
        }
    }
    
    func checkForExpiredCycle() {
        guard let currentCycle = appData.cycles.last else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        let challengeDate = Calendar.current.startOfDay(for: currentCycle.foodChallengeDate)
        
        if today >= challengeDate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showingCycleCompletionPopup = true
            }
        }
    }
    
    private func mainAppContentView() -> some View {
        Group {
            if authViewModel.authState == .loading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else if authViewModel.authState == .signedOut {
                NavigationView {
                    LoginView()
                        .environmentObject(authViewModel)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else if authViewModel.authState == .signedIn {
                // Check if we're in the middle of user creation process
                if authViewModel.showingNameInput {
                    // Show name input - DO NOT show timeout here
                    ZStack {
                        Color(UIColor.systemBackground)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            Spacer()
                            Text("Complete Your Setup")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Please enter your name to continue")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding()
                            Spacer()
                        }
                    }
                    // In ContentView.swift, find this section and replace it:

                    .sheet(isPresented: $authViewModel.showingNameInput) {
                        if let result = authViewModel.pendingAppleSignInResult {
                            NameInputView(
                                isPresented: $authViewModel.showingNameInput,
                                appleSignInResult: result,
                                onNameSubmitted: { name, email in // Updated to receive both name and email
                                    authViewModel.completeNameInput(name: name, email: email)
                                }
                            )
                        }
                    }
                } else if appData.currentUser != nil && appData.currentRoomId != nil {
                    // User is fully set up and has a room
                    mainTabView()
                } else if appData.currentUser != nil {
                    // User exists but no room selected
                    InitialRoomsAndSubscriptionsView(appData: appData)
                        .environmentObject(authViewModel)
                        .onAppear {
                         //   // print("Navigating to RoomSubscriptionManagementView, clearing timer")
                            appData.logToFile("Navigating to RoomSubscriptionManagementView, clearing timer")
                            stopTreatmentTimer(clearRoom: false)
                            if appData.currentRoomId != nil {
                                appData.currentRoomId = nil
                                UserDefaults.standard.removeObject(forKey: "currentRoomId")
                            }
                            NotificationCenter.default.addObserver(
                                forName: Notification.Name("NavigateToHomeTab"),
                                object: nil,
                                queue: .main
                            ) { _ in
                                self.selectedTab = 2 // Switch to Home tab
                            }
                        }
                } else {
                    // User is signed in to Firebase but app user doesn't exist yet
                    UserCreationLoadingView(appData: appData, authViewModel: authViewModel)
                }
            }
        }
    }
    
    func itemDisplayText(item: Item) -> String {
        appData.itemDisplayText(item: item)
    }
    
    private func mainTabView() -> some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                WeekView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "calendar")
                Text("Week")
            }
            .tag(0)
            
            NavigationView {
                ReactionsView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "exclamationmark.triangle")
                Text("Reactions")
            }
            .tag(1)
            
            NavigationView {
                mainContentView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(2)
            .onAppear {
                updateRecommendedItemCounts()
                if appData.currentRoomId != nil {
                    appData.checkRoomOwnerGracePeriod(roomId: appData.currentRoomId!)
                    appData.checkPendingOwnershipRequests()
                }
            }
            
            NavigationView {
                HistoryView(appData: appData)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "clock.arrow.circlepath")
                Text("History")
            }
            .tag(3)
            
            NavigationView {
                SettingsView(appData: appData)
            }
            .id(settingsNavigationId)
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
            .tag(4)
            .onChange(of: selectedTab) { newValue in
                if newValue == 4 {
                    settingsNavigationId = UUID()
                }
            }
        }
        .onReceive(timer) { _ in updateTimerCountdown() }
        .onAppear(perform: onAppearActions)
        .onChange(of: appData.consumptionLog) { _ in handleConsumptionLogChange() }
        .onChange(of: appData.treatmentTimer) { newValue in
            if let timer = newValue, timer.isActive, timer.endTime > Date() {
                resumeCurrentRoomTimer()
            } else {
                stopTimerForCurrentRoom()
            }
        }
        .onChange(of: appData.activeTimers) { _ in
            // Update treatmentCountdowns only for the current room
            if let roomId = appData.currentRoomId,
               let timer = appData.activeTimers[roomId],
               timer.isActive,
               timer.endTime > Date() {
                DispatchQueue.main.async {
                    self.treatmentCountdowns = [roomId: timer.endTime.timeIntervalSinceNow]
                    self.treatmentTimerId = timer.id
                    self.forceRefreshID = UUID()
                    print("Updated timer for current room \(roomId): \(timer.id)")
                }
            } else {
                DispatchQueue.main.async {
                    self.treatmentCountdowns.removeAll()
                    self.treatmentTimerId = nil
                    self.forceRefreshID = UUID()
                    print("No active timer for current room \(String(describing: appData.currentRoomId))")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ActiveTimerFound"))) { notification in
            if let timer = notification.object as? TreatmentTimer,
               let userInfo = notification.userInfo,
               let roomId = userInfo["roomId"] as? String,
               roomId == appData.currentRoomId,
               timer.isActive,
               timer.endTime > Date() {
                print("Received ActiveTimerFound for current room \(roomId), timer \(timer.id)")
                resumeCurrentRoomTimer()
            }
        }
    }
    
    private func resumeCurrentRoomTimer() {
        guard let roomId = appData.currentRoomId else {
            treatmentCountdowns.removeAll()
            treatmentTimerId = nil
            return
        }
        
        if let timer = appData.activeTimers[roomId], timer.isActive, timer.endTime > Date() {
            let remaining = max(timer.endTime.timeIntervalSinceNow, 0)
            if remaining <= 0 {
                print("Timer expired for room \(roomId), stopping")
                appData.stopTreatmentTimer(roomId: roomId)
                treatmentCountdowns.removeAll()
                treatmentTimerId = nil
                return
            }
            
            DispatchQueue.main.async {
                self.treatmentCountdowns = [roomId: remaining]
                self.treatmentTimerId = timer.id
                self.forceRefreshID = UUID()
                print("Resumed timer for room \(roomId): \(remaining)s remaining")
            }
            
            // Ensure notifications are scheduled
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                DispatchQueue.main.async {
                    if !requests.contains(where: { $0.identifier.hasPrefix(timer.id) }) {
                        print("Rescheduling notifications for timer \(timer.id) in room \(roomId)")
                        appData.snoozeTreatmentTimer(duration: remaining, roomId: roomId)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.treatmentCountdowns.removeAll()
                self.treatmentTimerId = nil
                self.forceRefreshID = UUID()
                print("No active timer to resume for room \(roomId)")
            }
        }
    }

    private func stopTimerForCurrentRoom() {
        guard let roomId = appData.currentRoomId else { return }
        
        appData.stopTreatmentTimer(roomId: roomId)
        treatmentCountdowns.removeAll()
        treatmentTimerId = nil
        showingTimerAlert = false
        forceRefreshID = UUID()
        print("Stopped timer for room \(roomId)")
    }

    private func updateTimerCountdown() {
        guard let roomId = appData.currentRoomId else {
            treatmentCountdowns.removeAll()
            return
        }
        
        // Only process current room's timer
        if let timer = appData.activeTimers[roomId], timer.isActive {
            let remaining = timer.endTime.timeIntervalSinceNow
            
            // NEW: Update Live Activity progress every second while active
            if remaining > 3, #available(iOS 16.1, *) {
                appData.updateLiveActivityProgress(
                    roomId: roomId,
                    endTime: timer.endTime,
                    isActive: true,
                    totalDuration: appData.getEffectiveTreatmentTimerDuration()
                )
            }
            
            // FIXED: Update Live Activity EARLIER at 3 seconds remaining to prevent counting up
            if remaining <= 3 && !showingTimerAlert && !isCategoryComplete(.treatment) {
                // Update Live Activity immediately to show expired state
                if #available(iOS 16.1, *) {
                    appData.updateExpiredLiveActivity(
                        roomId: roomId,
                        endTime: timer.endTime,
                        totalDuration: appData.getEffectiveTreatmentTimerDuration()
                    )
                }
            }
            
            // Handle final expiration for alerts
            if remaining <= 1 && !showingTimerAlert && !isCategoryComplete(.treatment) {
                NotificationHelper.playSystemSound()
                
                DispatchQueue.main.async {
                    self.showingTimerAlert = true
                }
            }
            
            // Update countdown - only if timer hasn't expired
            if remaining > 0 {
                treatmentCountdowns = [roomId: remaining]
            } else {
                // Timer fully expired - clean up
                appData.stopTreatmentTimer(roomId: roomId)
                treatmentCountdowns.removeAll()
            }
        } else {
            treatmentCountdowns.removeAll()
        }
    }
    
    private func updateRecommendedItemCounts() {
        if let cycleId = appData.currentCycleId() {
            let (weekStart, weekEnd) = currentWeekRange()
            let items = currentItems().filter { $0.category == .recommended }
            
            var newCounts: [UUID: Int] = [:]
            
            for item in items {
                let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
                let count = logs.filter { $0.date >= weekStart && $0.date <= weekEnd }.count
                newCounts[item.id] = count
                // print("Updated weekly count for \(item.name): \(count)")
            }
            
            DispatchQueue.main.async {
                self.recommendedWeeklyCounts = newCounts
                // print("Updated recommendedWeeklyCounts: \(newCounts)")
                self.forceRefreshID = UUID()
            }
        }
    }
    
    private func headerView() -> some View {
        VStack {
            HStack(alignment: .center) {
                if let cycleId = appData.currentCycleId(),
                   let profileImage = appData.loadProfileImage(forCycleId: cycleId) {
                    Image(uiImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 70, height: 70)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentPatientName())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    let (cycle, week, day) = currentWeekAndDay()
                    Text("Cycle \(cycle) • Week \(week) • Day \(day)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if notificationPermissionDenied {
                Text("Notifications are disabled. Go to iOS Settings > Notifications > TIPs App to enable them.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .padding(.top)
    }
    
    private func categoriesScrollView() -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .padding()
                    }
                    Spacer()
                }
                .frame(height: isRefreshing ? 40 : 0)
                
                LazyVStack(spacing: 12) {
                    // Grace Period Alert Card - Owner
                    if appData.isInGracePeriod, let gracePeriodEnd = appData.subscriptionGracePeriodEnd {
                        ownerGracePeriodAlertCard(gracePeriodEnd: gracePeriodEnd)
                    }

                    // Grace Period Alert Card - Invited User
                    if appData.roomOwnerInGracePeriod, let gracePeriodEnd = appData.roomOwnerGracePeriodEnd {
                        invitedUserGracePeriodAlertCard(gracePeriodEnd: gracePeriodEnd)
                    }
                    
                    categorySection(for: .medicine)
                    categorySection(for: .maintenance)
                    treatmentCategorySection()
                    categorySection(for: .recommended)
                }
                .padding(.bottom, 60)
                .id(forceRefreshID)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollViewOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("scrollview")).origin.y
                    )
                }
            )
            .onPreferenceChange(ScrollViewOffsetPreferenceKey.self) { offset in
                if offset > 50 && !isRefreshing {
                    isRefreshing = true
                    updateRecommendedItemCounts()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRefreshing = false
                    }
                }
            }
        }
        .coordinateSpace(name: "scrollview")
    }
    
    private func ownerGracePeriodAlertCard(gracePeriodEnd: Date) -> some View {
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscription Cancelled")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if appData.hasPendingOwnershipRequests {
                        Text("Someone has requested ownership of your room! You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("Your subscription has been cancelled. You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining to resubscribe.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                Spacer()
            }
            
            if !appData.hasPendingOwnershipRequests {
                Text("If you don't resubscribe, your rooms and all data will be permanently deleted.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    showingSubscriptionManagement = true
                }) {
                    HStack {
                        Image(systemName: "creditcard")
                        Text("Resubscribe Now")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(8)
                }
                
                if appData.hasPendingOwnershipRequests {
                    Button(action: {
                        // Navigate to Settings tab and then to Transfer Requests
                        selectedTab = 4
                    }) {
                        HStack {
                            Image(systemName: "person.2")
                            Text("View Requests")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func invitedUserGracePeriodAlertCard(gracePeriodEnd: Date) -> some View {
        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room Owner's Subscription Cancelled")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("The room owner's subscription was cancelled. This room will be deleted in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") unless someone takes ownership.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
            }
            
            Text("You can request ownership to save this room and its data.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            HStack(spacing: 12) {
                Button(action: {
                    requestRoomOwnership()
                }) {
                    HStack {
                        if isRequestingOwnership {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "hand.raised")
                        }
                        Text(isRequestingOwnership ? "Requesting..." : "Request Ownership")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(8)
                }
                .disabled(isRequestingOwnership)
                
                // NEW: Show sent requests button
                Button(action: {
                    selectedTab = 4 // Navigate to Settings to see transfer requests
                }) {
                    HStack {
                        Image(systemName: "paperplane")
                        Text("View Sent")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .alert("Upgrade Required", isPresented: $showingOwnershipUpgradeAlert) {
            Button("Upgrade Subscription") {
                showingSubscriptionManagement = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You need a subscription to take ownership of this room. Would you like to upgrade now?")
        }
        .alert("Request Sent", isPresented: $showingOwnershipSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Your ownership request has been sent to the room owner. They will be notified and can approve your request.")
        }
        .alert("Error", isPresented: $showingOwnershipErrorAlert) {
            Button("OK") { }
        } message: {
            Text(ownershipErrorMessage ?? "An error occurred")
        }
    }

    private func requestRoomOwnership() {
        guard let roomId = appData.currentRoomId else {
            // print("No current room ID for ownership request")
            return
        }
        
        // print("Requesting ownership for room: \(roomId)")
        isRequestingOwnership = true
        
        appData.requestRoomOwnership(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                self.isRequestingOwnership = false
                
                if success {
                    // print("Ownership request successful")
                    self.showingOwnershipSuccessAlert = true
                } else if error == "UPGRADE_NEEDED" {
                    // print("Upgrade needed for ownership request")
                    self.showingOwnershipUpgradeAlert = true
                } else {
                    // print("Ownership request failed: \(error ?? "unknown error")")
                    self.ownershipErrorMessage = error ?? "Failed to request ownership"
                    self.showingOwnershipErrorAlert = true
                }
            }
        }
    }
    
    func categorySection(for category: Category) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Image(systemName: category.icon)
                        .foregroundColor(category.iconColor)
                        .font(.title3)
                    Text(category.rawValue)
                        .font(.headline)
                        .bold()
                        .foregroundColor(.primary)
                    Spacer()
                    TimeOfDayTag(text: timeOfDay(for: category), color: category.iconColor)
                }
                if !isCollapsed(category) {
                    let cycleId = appData.currentCycleId() ?? UUID()
                    let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }
                    let items = currentItems().filter { $0.category == category }
                    
                    ForEach(groups, id: \.id) { group in
                        GroupView(appData: appData, group: group, cycleId: cycleId, items: items, weeklyCounts: recommendedWeeklyCounts, forceRefreshID: $forceRefreshID)
                    }
                    
                    let standaloneItems = items.filter { item in
                        !groups.contains(where: { $0.itemIds.contains(item.id) })
                    }
                    ForEach(standaloneItems, id: \.id) { item in
                        if category == .recommended {
                            recommendedItemRow(item: item, weeklyCount: recommendedWeeklyCounts[item.id] ?? 0, isGroupItem: false, groupChecked: false)
                        } else {
                            itemRow(item: item, category: category, isGroupItem: false, groupChecked: false)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }
    
    func treatmentCategorySection() -> some View {
        treatmentCategoryView()
    }
    
    func categoryView(for category: Category) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.iconColor)
                    .font(.title3)
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                TimeOfDayTag(text: timeOfDay(for: category), color: category.iconColor)
            }
            .padding(.top, 10)
            if !isCollapsed(category) {
                let cycleId = appData.currentCycleId() ?? UUID()
                let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }
                let items = currentItems().filter { $0.category == category }
                
                ForEach(groups, id: \.id) { group in
                    GroupView(appData: appData, group: group, cycleId: cycleId, items: items, weeklyCounts: recommendedWeeklyCounts, forceRefreshID: $forceRefreshID)
                }
                let standaloneItems = items.filter { item in
                    !groups.contains(where: { $0.itemIds.contains(item.id) })
                }
                if standaloneItems.isEmpty && groups.isEmpty {
                    Text("No items added")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(standaloneItems, id: \.id) { item in
                        if category == .recommended {
                            recommendedItemRow(item: item, weeklyCount: recommendedWeeklyCounts[item.id] ?? 0, isGroupItem: false, groupChecked: false)
                        } else {
                            itemRow(item: item, category: category, isGroupItem: false, groupChecked: false)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggleCollapse(category) }
    }
    
    func treatmentCategoryView() -> some View {
        let cycleId = appData.currentCycleId() ?? UUID()
        let items = currentItems().filter { $0.category == .treatment }
        let today = Calendar.current.startOfDay(for: Date())
        let hasUnloggedItems = items.contains { item in
            !(appData.consumptionLog[cycleId]?[item.id] ?? []).contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
        
        return VStack(alignment: .leading) {
            HStack {
                Image(systemName: Category.treatment.icon)
                    .foregroundColor(Category.treatment.iconColor)
                    .font(.title3)
                Text(Category.treatment.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("Evening")
                    .timeOfDayTagStyle(color: Category.treatment.iconColor)
            }
            .padding(.bottom, 4)
            
            if hasUnloggedItems, let currentRoomId = appData.currentRoomId, let countdown = treatmentCountdowns[currentRoomId], countdown > 0 {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundColor(.purple)
                        Text(formattedTimeRemaining(countdown))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(.purple)
                    }
                    ProgressView(value: 1.0 - (countdown / appData.getEffectiveTreatmentTimerDuration()))
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.purple)
                        .frame(height: 6)
                        .padding(.horizontal)
                    Text("Treatment in Progress")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(12)
            }
            
            let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == .treatment }
            ForEach(groups, id: \.id) { group in
                GroupView(
                    appData: appData,
                    group: group,
                    cycleId: cycleId,
                    items: items,
                    weeklyCounts: [:],
                    forceRefreshID: $forceRefreshID
                )
            }
            
            let standaloneItems = items.filter { item in
                !groups.contains(where: { group in group.itemIds.contains(item.id) })
            }
            if standaloneItems.isEmpty && groups.isEmpty {
                Text("No items added")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(standaloneItems, id: \.id) { item in
                    itemRow(item: item, category: .treatment, isGroupItem: false, groupChecked: false)
                }
            }
        }
        .cardStyle()
    }
    
    func headerView(for category: Category) -> some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(category.iconColor)
                .font(.title3)
            Text(category.rawValue)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Text(timeOfDay(for: category))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 10)
    }
    
    func standaloneItemsView(items: [Item], groups: [GroupedItem]) -> some View {
        let standaloneItems = items.filter { item in
            !groups.contains(where: { $0.itemIds.contains(item.id) })
        }
        return Group {
            if standaloneItems.isEmpty && groups.isEmpty {
                Text("No items added")
                    .foregroundColor(.secondary)
            } else {
                ForEach(standaloneItems, id: \.id) { item in
                    itemRow(item: item, category: .treatment, isGroupItem: false, groupChecked: false)
                }
            }
        }
    }
    
    func itemRow(item: Item, category: Category, isGroupItem: Bool, groupChecked: Bool) -> some View {
        HStack {
            if !isGroupItem {
                Spacer().frame(width: 20)
            }
            Button(action: { toggleCheck(item: item) }) {
                Image(systemName: isItemCheckedToday(item) ? "checkmark.square.fill" : "square")
                    .foregroundColor(isItemCheckedToday(item) ? .secondary : .blue)
                    .font(.title3)
                    .accessibilityLabel(isItemCheckedToday(item) ? "Checked" : "Unchecked")
            }
            .disabled(isGroupItem && groupChecked)
            
            HStack(spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                if (item.category == .treatment || item.category == .medicine), let weeklyDoses = item.weeklyDoses {
                    let currentWeek = getCurrentWeek()
                    let doseKey = getWeeklyDoseKey()
                    
                    let _ = {
                        print("=== DEBUG WEEKLY DOSE LOOKUP ===")
                        print("Item: \(item.name)")
                        print("Current week: \(currentWeek)")
                        print("Dose key: \(doseKey)")
                        print("Available weekly dose keys: \(weeklyDoses.keys.sorted())")
                        print("Looking for key: \(doseKey)")
                        return ""
                    }()
                    
                    if let weekData = weeklyDoses[doseKey] {
                        let _ = print("FOUND dose for key \(doseKey): \(weekData.dose) \(weekData.unit)")
                        Text("- \(formatDose(weekData.dose)) \(weekData.unit) (Week \(currentWeek))")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        let _ = print("NOT FOUND - falling back to closest week logic")
                        let weeks = weeklyDoses.keys.sorted()
                        if let closestWeek = weeks.last(where: { $0 <= doseKey }) ?? weeks.first,
                           let weekData = weeklyDoses[closestWeek] {
                            let displayWeek = closestWeek - 1
                            Text("- \(formatDose(weekData.dose)) \(weekData.unit) (Week \(displayWeek))")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let dose = item.dose, let unit = item.unit {
                    Text("- \(formatDose(dose)) \(unit)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 8)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    func getCurrentWeek() -> Int {
        guard let currentCycle = appData.cycles.last else { return 1 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: currentCycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        return (daysSinceStart / 7) + 1
    }

    func getWeeklyDoseKey() -> Int {
        return getCurrentWeek()
    }
    
    func recommendedItemRow(item: Item, weeklyCount: Int, isGroupItem: Bool, groupChecked: Bool) -> some View {
        // Determine if this item is part of a group (for the temporary fix)
        let isInGroup = isGroupItem || {
            guard let cycleId = appData.currentCycleId() else { return false }
            let groups = appData.groupedItems[cycleId] ?? []
            return groups.contains { $0.itemIds.contains(item.id) }
        }()
        
        // Calculate display count and completion threshold based on requirements
        let displayCount: Int
        let completionThreshold: Int
        
        if isInGroup {
            // For grouped recommended items: always show /5, complete at 3
            displayCount = 5
            completionThreshold = 3
        } else if item.scheduleType != nil {
            // For standalone items with advanced scheduling: show actual scheduled days, complete when all are done
            displayCount = appData.expectedWeeklyCount(item)
            completionThreshold = appData.expectedWeeklyCount(item)
        } else {
            // For standalone items without advanced scheduling: show /5, complete at 3
            displayCount = 5
            completionThreshold = 3
        }
        
        let progress = displayCount > 0 ? min(Double(weeklyCount) / Double(displayCount), 1.0) : 0.0
        let isComplete = weeklyCount >= completionThreshold
        
        @State var animatedColor: Color = isComplete ? .green : Category.recommended.progressBarColor
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !isGroupItem {
                    Spacer().frame(width: 20)
                }
                Button(action: { toggleCheck(item: item) }) {
                    Image(systemName: isItemCheckedToday(item) ? "checkmark.square.fill" : "square")
                        .foregroundColor(isItemCheckedToday(item) ? .secondary : .blue)
                        .font(.title3)
                        .accessibilityLabel(isItemCheckedToday(item) ? "Checked" : "Unchecked")
                }
                .disabled(isGroupItem && groupChecked)
                
                Text(item.name)
                    .font(.body)
                    .foregroundColor(isComplete ? .green : .primary)  // Green text when complete
                
                if let dose = item.dose, let unit = item.unit {
                    Text("- \(formatDose(dose)) \(unit)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .tint(animatedColor)
                .frame(height: 5)
                .onChange(of: weeklyCount) { newValue in
                    let newCompletionThreshold: Int
                    if isInGroup {
                        newCompletionThreshold = 3
                    } else if item.scheduleType != nil {
                        newCompletionThreshold = appData.expectedWeeklyCount(item)
                    } else {
                        newCompletionThreshold = 3
                    }
                    
                    let isComplete = newValue >= newCompletionThreshold
                    withAnimation(.easeInOut(duration: 0.4)) {
                        animatedColor = isComplete ? .green : Category.recommended.progressBarColor
                    }
                }
            
            Text("\(weeklyCount)/\(displayCount) this week")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            let initialCompletionThreshold: Int
            if isInGroup {
                initialCompletionThreshold = 3
            } else if item.scheduleType != nil {
                initialCompletionThreshold = appData.expectedWeeklyCount(item)
            } else {
                initialCompletionThreshold = 3
            }
            
            animatedColor = weeklyCount >= initialCompletionThreshold ? .green : Category.recommended.progressBarColor
        }
    }
    
    func isCollapsed(_ category: Category) -> Bool {
        // Categories should never auto-collapse - only collapse if manually set by user
        return appData.categoryCollapsed[category.rawValue] ?? false
    }
    
    func toggleCollapse(_ category: Category) {
        appData.setCategoryCollapsed(category, isCollapsed: !isCollapsed(category))
    }
    
    func currentCycleNumber() -> Int {
        appData.cycles.last?.number ?? 0
    }
    
    func currentPatientName() -> String {
        appData.cycles.last?.patientName ?? "TIPs"
    }
    
    func isCategoryComplete(_ category: Category) -> Bool {
        let items = currentItems().filter { $0.category == category }
        return !items.isEmpty && items.allSatisfy { isItemCheckedToday($0) }
    }
    
    func isItemCheckedToday(_ item: Item) -> Bool {
        let today = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        
        for cycle in appData.cycles {
            let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
            let cycleEndDay = calendar.startOfDay(for: cycle.foodChallengeDate)
            
            if todayStart >= cycleStartDay && todayStart <= cycleEndDay {
                let logs = appData.consumptionLog[cycle.id]?[item.id] ?? []
                let isChecked = logs.contains { log in
                    let logDay = calendar.startOfDay(for: log.date)
                    return logDay == todayStart
                }
                return isChecked
            }
        }
        
        let mostRecentCycle = appData.cycles.filter {
            calendar.startOfDay(for: $0.startDate) <= todayStart
        }.max(by: {
            $0.startDate < $1.startDate
        })
        
        if let cycleId = mostRecentCycle?.id {
            let logs = appData.consumptionLog[cycleId]?[item.id] ?? []
            let isChecked = logs.contains { log in
                let logDay = calendar.startOfDay(for: log.date)
                return logDay == todayStart
            }
            // print("Between cycles check for item \(item.id) on \(todayStart) in cycle \(cycleId) = \(isChecked)")
            return isChecked
        }
        
        return false
    }
    
    func isGroupCheckedToday(_ group: GroupedItem) -> Bool {
        guard let cycleId = appData.currentCycleId() else { return false }
        let items = currentItems().filter { group.itemIds.contains($0.id) }
        return items.allSatisfy { isItemCheckedToday($0) }
    }
    
    func weeklyDoseCount(for item: Item) -> Int {
        guard let cycleId = appData.currentCycleId() else { return 0 }
        let (weekStart, weekEnd) = currentWeekRange()
        return appData.consumptionLog[cycleId]?[item.id]?.filter { $0.date >= weekStart && $0.date <= weekEnd }.count ?? 0
    }
    
    func currentWeekRange() -> (start: Date, end: Date) {
        guard let cycle = appData.cycles.last else {
            let now = Date()
            let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
            let weekEndEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd)!
            // print("No cycle, week range: \(weekStart) to \(weekEndEndOfDay)")
            return (weekStart, weekEndEndOfDay)
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        let currentWeekOffset = (daysSinceStart / 7)
        let weekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: cycleStartDay)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let weekEndEndOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd)!
        // print("Cycle start: \(cycle.startDate), today: \(today), week range: \(weekStart) to \(weekEndEndOfDay), local timezone: \(TimeZone.current.identifier)")
        return (weekStart, weekEndEndOfDay)
    }
    
    func progressBarColor(for count: Int) -> Color {
        switch count {
        case 0..<3: return .blue
        case 3...5: return .green
        default: return .red
        }
    }
    
    func toggleCheck(item: Item) {
        let today = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        let currentCycleId: UUID? = appData.cycles.first(where: { cycle in
            let cycleStart = calendar.startOfDay(for: cycle.startDate)
            let cycleEnd = calendar.startOfDay(for: cycle.foodChallengeDate)
            return todayStart >= cycleStart && todayStart <= cycleEnd
        })?.id ?? appData.cycles.filter {
            calendar.startOfDay(for: $0.startDate) <= todayStart
        }.max(by: {
            $0.startDate < $1.startDate
        })?.id
        
        guard let cycleId = currentCycleId else {
            // print("No cycle ID available, skipping toggleCheck for item \(item.id)")
            return
        }
        
        let isChecked = isItemCheckedToday(item)
        // print("toggleCheck: Item \(item.id) (\(item.name)), isChecked: \(isChecked)")
        
        if isChecked {
            if let log = appData.consumptionLog[cycleId]?[item.id]?.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                appData.removeIndividualConsumption(itemId: item.id, cycleId: cycleId, date: log.date)
                // print("Unchecked item \(item.id), log removed for \(log.date)")
            }
            
            if item.category == .treatment {
                // print("Unchecking treatment item, stopping timer")
                stopTreatmentTimer(clearRoom: true)
            }
        } else {
            appData.logIndividualConsumption(itemId: item.id, cycleId: cycleId)
            // print("Logged item \(item.id) for today in cycle \(cycleId)")
            // Track item logging
                TelemetryDeck.signal("item.logged", parameters: ["category": item.category.rawValue])
            
            if item.category == .treatment {
                let treatmentItems = currentItems().filter { $0.category == .treatment }
                let unloggedTreatmentItems = treatmentItems.filter { !isItemCheckedToday($0) || $0.id == item.id }
                
                if unloggedTreatmentItems.count <= 1 {
                    // print("Checked last treatment item \(item.id), stopping timer")
                    stopTreatmentTimer(clearRoom: true)
                } else {
                    // print("Checked treatment item \(item.id), restarting timer (\(unloggedTreatmentItems.count - 1) items remain)")
                    startTreatmentTimer()
                }
            }
        }
        
     //   if let category = Category(rawValue: item.category.rawValue) {
      //      appData.setCategoryCollapsed(category, isCollapsed: isCategoryComplete(category))
      //  }
        
        if item.category == .recommended {
            updateRecommendedItemCounts()
        }
        
        forceRefreshID = UUID()
        appData.objectWillChange.send()
    }
    
    func startTreatmentTimer() {
        guard let roomId = appData.currentRoomId else { return }
        appData.stopTreatmentTimer(roomId: roomId)
        
        if isCategoryComplete(.treatment) {
            // print("All treatment items logged for room \(roomId), not starting timer")
            return
        }
        
        let duration = appData.getEffectiveTreatmentTimerDuration()
        appData.startTreatmentTimer(duration: duration, roomId: roomId)
        treatmentCountdowns[roomId] = duration
        treatmentTimerId = appData.treatmentTimerId
        forceRefreshID = UUID()
        
        // Debug notifications
        appData.debugNotificationStatus()
    }
    
    func resumeTreatmentTimer() {
        var newCountdowns: [String: TimeInterval] = [:]
        for (roomId, timer) in appData.activeTimers where timer.isActive && timer.endTime > Date() {
            let remaining = max(timer.endTime.timeIntervalSinceNow, 0)
            if remaining <= 0 {
                // print("Timer expired for room \(roomId), stopping")
                appData.logToFile("Timer expired for room \(roomId), stopping")
                appData.stopTreatmentTimer(roomId: roomId)
                continue
            }
            
            newCountdowns[roomId] = remaining
            if roomId == appData.currentRoomId {
                treatmentTimerId = timer.id
                appData.treatmentTimerId = timer.id
            }
            
            // Ensure notifications are scheduled
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                DispatchQueue.main.async {
                    if !requests.contains(where: { $0.identifier.hasPrefix(timer.id) }) {
                        // print("Rescheduling notifications for timer \(timer.id) in room \(roomId)")
                        appData.logToFile("Rescheduling notifications for timer \(timer.id) in room \(roomId)")
                        appData.snoozeTreatmentTimer(duration: remaining, roomId: roomId)
                    } else {
                        // print("Notifications already scheduled for timer \(timer.id)")
                        appData.logToFile("Notifications already scheduled for timer \(timer.id)")
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.treatmentCountdowns = newCountdowns
            self.forceRefreshID = UUID()
            self.appData.objectWillChange.send()
            // print("Updated countdowns: \(newCountdowns)")
            appData.logToFile("Updated countdowns: \(newCountdowns)")
        }
    }
    
    func stopTreatmentTimer(clearRoom: Bool = false, roomId: String? = nil) {
        let targetRoomId = roomId ?? appData.currentRoomId
        guard let roomId = targetRoomId else { return }
        
        appData.stopTreatmentTimer(clearRoom: clearRoom, roomId: roomId)
        
        // Update the countdown for this specific room
        treatmentCountdowns.removeValue(forKey: roomId)
        
        // Only clear the timer ID if it's for the current room
        if roomId == appData.currentRoomId {
            treatmentTimerId = nil
        }
        
        showingTimerAlert = false
        forceRefreshID = UUID()
    }
    
    func handleConsumptionLogChange() {
        let wasComplete = isCategoryComplete(.treatment)
    //    appData.setCategoryCollapsed(.treatment, isCollapsed: isCategoryComplete(.treatment))
        let isCompleteNow = isCategoryComplete(.treatment)
        
        if wasComplete && !isCompleteNow {
            // print("Consumption changed, treatment incomplete, starting timer")
            startTreatmentTimer()
        } else if !wasComplete && isCompleteNow {
            // print("Consumption changed, treatment complete, stopping timer")
            stopTreatmentTimer()
        }
        
        updateRecommendedItemCounts()
        
        appData.objectWillChange.send()
        forceRefreshID = UUID()
    }
    
    func updateTreatmentCountdown() {
        var newCountdowns: [String: TimeInterval] = [:]
        
        for (roomId, timer) in appData.activeTimers where timer.isActive {
            let remaining = timer.endTime.timeIntervalSinceNow
            
            // REMOVED: Duplicate expiration handling that caused race condition
            // The expiration is now only handled in updateTimerCountdown()
            
            if remaining > 0 {
                newCountdowns[roomId] = remaining
            } else {
                // Only clean up the timer, don't handle live activity here
                appData.stopTreatmentTimer(roomId: roomId)
            }
        }
        
        // Remove countdown for completed treatment rooms
        if isCategoryComplete(.treatment) {
            newCountdowns.removeValue(forKey: appData.currentRoomId ?? "")
        }
        
        treatmentCountdowns = newCountdowns
    }
    
    func onAppearActions() {
        // Track app open
        TelemetryDeck.signal("app.opened")
        // Check room owner grace period status
        if appData.currentRoomId != nil {
            appData.checkRoomOwnerGracePeriod(roomId: appData.currentRoomId!)
            appData.checkPendingOwnershipRequests()
        }
        if UserDefaults.standard.bool(forKey: "showFirstCyclePopup") {
            if let cycleIdString = UserDefaults.standard.string(forKey: "newCycleId"),
               let cycleId = UUID(uuidString: cycleIdString),
               let existingCycle = appData.cycles.first(where: { $0.id == cycleId }) {
                // Use existing cycle from CreateRoomView
                self.newCycle = existingCycle
                self.showingFirstCyclePopup = true
            }
        } else if UserDefaults.standard.bool(forKey: "showFirstCyclePopup"),
                  let cycleIdString = UserDefaults.standard.string(forKey: "newCycleId"),
                  let cycleId = UUID(uuidString: cycleIdString) {
            if let cycle = appData.cycles.first(where: { $0.id == cycleId }) {
                self.newCycle = cycle
                self.showingFirstCyclePopup = true
            } else {
                if let roomId = appData.currentRoomId, let dbRef = appData.valueForDBRef() {
                    dbRef.child("cycles").child(cycleId.uuidString).observeSingleEvent(of: .value) { snapshot in
                        if let cycleDict = snapshot.value as? [String: Any],
                           let cycle = Cycle(dictionary: cycleDict) {
                            DispatchQueue.main.async {
                                self.appData.cycles = [cycle]
                                self.newCycle = cycle
                                self.showingFirstCyclePopup = true
                            }
                        }
                    }
                }
            }
        }
        
        if authViewModel.authState == .signedIn, let authUser = authViewModel.currentUser {
            if appData.currentUser == nil {
                createUserFromAuth(authUser: authUser)
            }
        }
        
     //   // print("Checking timer state on appear")
        appData.logToFile("Checking timer state on appear")
        appData.loadTimerState()
        if let timer = appData.treatmentTimer, timer.isActive, timer.endTime > Date() {
          //  // print("Found active timer on appear: \(timer.id), remaining: \(timer.endTime.timeIntervalSinceNow)s")
            appData.logToFile("Found active timer on appear: \(timer.id), remaining: \(timer.endTime.timeIntervalSinceNow)s")
            resumeTreatmentTimer()
        } else {
         //   // print("No active timer on appear, checking Firebase")
            appData.logToFile("No active timer on appear, checking Firebase")
            appData.checkForActiveTimers()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.appData.currentRoomId != nil {
             //   // print("Periodic timer check")
                self.appData.logToFile("Periodic timer check")
                self.appData.checkForActiveTimers()
                if let timer = self.appData.treatmentTimer, timer.isActive, timer.endTime > Date() {
                  //  // print("Periodic check found timer: \(timer.id)")
                    self.appData.logToFile("Periodic check found timer: \(timer.id)")
                    self.resumeTreatmentTimer()
                    self.forceRefreshID = UUID()
                }
            }
        }
        
        showingPrivacyStatement = !UserDefaults.standard.bool(forKey: "hasAcceptedPrivacyPolicy")
        initializeCollapsedState()
        checkNotificationPermissions()
        appData.checkAndResetIfNeeded()
        showingSyncError = appData.syncError != nil
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AuthUserSignedIn"),
            object: nil,
            queue: .main
        ) { notification in
           // // print("ContentView: Received AuthUserSignedIn notification")
            if let userInfo = notification.userInfo,
               let appUser = userInfo["appUser"] as? User {
              //  // print("ContentView: Setting current user from notification: \(appUser.name)")
                self.appData.currentUser = appUser
                
                // Save to UserDefaults
                UserDefaults.standard.set(appUser.id.uuidString, forKey: "currentUserId")
                
                // Force UI update
                DispatchQueue.main.async {
                    self.forceRefreshID = UUID()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UserDidSignOut"),
            object: nil,
            queue: .main
        ) { _ in
            self.isLoggedIn = false
            self.appData.currentUser = nil
            self.appData.currentRoomId = nil
        }
        
        observeTimer()
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("RoomJoined"),
            object: nil,
            queue: .main
        ) { _ in
            self.appData.loadFromFirebase()
            self.forceRefreshID = UUID()
        }
        
        // NEW: Setup Live Activity observer when joining rooms
        NotificationCenter.default.addObserver(
            forName: Notification.Name("RoomJoined"),
            object: nil,
            queue: .main
        ) { _ in
            if #available(iOS 16.1, *) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.appData.setupLiveActivityObserver()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AuthUserSignedIn"),
            object: nil,
            queue: .main
        ) { notification in
           // // print("Received AuthUserSignedIn notification in ContentView")
            if let userInfo = notification.userInfo,
               let appUser = userInfo["appUser"] as? User {
               // // print("Setting current user from notification: \(appUser.name)")
                self.appData.currentUser = appUser
                
                // Force UI update
                DispatchQueue.main.async {
                    self.forceRefreshID = UUID()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("GracePeriodStatusChanged"),
            object: nil,
            queue: .main
        ) { _ in
            // Force refresh grace period status
            if let roomId = self.appData.currentRoomId {
                self.appData.checkRoomOwnerGracePeriod(roomId: roomId)
            }
            self.forceRefreshID = UUID()
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("TransferRequestReceived"),
            object: nil,
            queue: .main
        ) { notification in
            // Refresh pending requests when a new one is received
            self.appData.checkPendingOwnershipRequests()
            
            // If this is for the current user, also refresh their transfer requests
            if let userInfo = notification.userInfo,
               let ownerId = userInfo["ownerId"] as? String,
               ownerId == self.appData.currentUser?.id.uuidString {
                self.appData.loadTransferRequests()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("RoomCreated"),
            object: nil,
            queue: .main
        ) { notification in
          //  // print("RoomCreated notification received!")
            appData.logToFile("RoomCreated notification received!")
            if let userInfo = notification.userInfo,
               let roomId = userInfo["roomId"] as? String,
               let cycle = userInfo["cycle"] as? Cycle {
              //  // print("Room ID: \(roomId), Cycle: \(cycle)")
                appData.logToFile("Room ID: \(roomId), Cycle: \(cycle)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.newCycle = cycle
                    self.showingFirstCyclePopup = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowFirstCyclePopup"),
            object: nil,
            queue: .main
        ) { _ in
            let cycleId = UUID()
            let participantName = UserDefaults.standard.string(forKey: "pendingParticipantName") ?? "Participant"
            
            let defaultCycle = Cycle(
                id: cycleId,
                number: 1,
                patientName: participantName,
                startDate: Date(),
                foodChallengeDate: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())!
            )
            
           // // print("Creating new cycle for first cycle popup")
            appData.logToFile("Creating new cycle for first cycle popup")
            self.newCycle = defaultCycle
            self.showingFirstCyclePopup = true
            
            if let imageData = UserDefaults.standard.data(forKey: "pendingProfileImage"),
               let profileImage = UIImage(data: imageData) {
                self.appData.saveProfileImage(profileImage, forCycleId: cycleId)
            }
            
            UserDefaults.standard.set(cycleId.uuidString, forKey: "newCycleId")
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NavigateToHomeTab"),
            object: nil,
            queue: .main
        ) { _ in
            self.selectedTab = 2 // Switch to Home tab
        }
        
        updateRecommendedItemCounts()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let timer = self.appData.treatmentTimer, timer.isActive, timer.endTime > Date() {
               // // print("Delayed timer check found timer: \(timer.id)")
                self.appData.logToFile("Delayed timer check found timer: \(timer.id)")
                self.resumeTreatmentTimer()
                self.forceRefreshID = UUID()
            } else {
              //  // print("Delayed timer check found no timer")
                self.appData.logToFile("Delayed timer check found no timer")
            }
        }
    }
    
    func dismissFirstCyclePopup() {
        showingFirstCyclePopup = false
        UserDefaults.standard.set(false, forKey: "showFirstCyclePopup")
        UserDefaults.standard.removeObject(forKey: "newCycleId")
        
        UserDefaults.standard.removeObject(forKey: "pendingParticipantName")
        UserDefaults.standard.removeObject(forKey: "pendingProfileImage")
        
        appData.objectWillChange.send()
        forceRefreshID = UUID()
    }
    
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionDenied = settings.authorizationStatus == .denied
            }
        }
    }
    
    func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func createUserFromAuth(authUser: AuthUser) {
        let userId = UUID()
        let displayName = authUser.displayName ?? "User"
        
        let newUser = User(
            id: userId,
            name: displayName
        )
        
        appData.addUser(newUser)
        appData.currentUser = newUser
        UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
        
        if let dbRef = appData.valueForDBRef() {
            dbRef.child("auth_mapping").child(authUser.uid).setValue(userId.uuidString)
            dbRef.child("users").child(userId.uuidString).child("authId").setValue(authUser.uid)
        }
    }
    
    func formatDose(_ dose: Double) -> String {
        if dose == 1.0 {
            return "1"
        } else if let fraction = Fraction.fractionForDecimal(dose) {
            return fraction.displayString
        } else if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%d", Int(dose))
        }
        return String(format: "%.1f", dose)
    }
    
    func currentWeekAndDay() -> (cycle: Int, week: Int, day: Int) {
        guard let currentCycle = appData.cycles.last else { return (cycle: 1, week: 1, day: 1) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: currentCycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        let week = (daysSinceStart / 7) + 1
        let day = (daysSinceStart % 7) + 1
        // print("ContentView week calc: cycle start \(cycleStartDay), today \(today), daysSinceStart \(daysSinceStart), week \(week), day \(day)")
        return (cycle: currentCycle.number, week: week, day: day)
    }
    
    func initializeCollapsedState() {
        Category.allCases.forEach { category in
            if appData.categoryCollapsed[category.rawValue] == nil {
                appData.setCategoryCollapsed(category, isCollapsed: isCategoryComplete(category))
            }
        }
    }
    
    func timeOfDay(for category: Category) -> String {
        switch category {
        case .medicine, .maintenance: return "Morning"
        case .treatment: return "Evening"
        case .recommended: return "Anytime"
        }
    }
    
    func currentItems() -> [Item] {
        guard let cycleId = appData.currentCycleId() else { return [] }
        let allItems = (appData.cycleItems[cycleId] ?? []).sorted { $0.order < $1.order }
        let today = Date()
        return allItems.filter { item in
            appData.isItemScheduledForDate(item, today)
        }
    }
    
    private func scheduleNotification(duration: TimeInterval) {
        guard let roomId = appData.currentRoomId,
              appData.currentUser?.roomSettings?[roomId]?.treatmentFoodTimerEnabled ?? false else {
            // print("Notifications not enabled for user, skipping scheduling")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let baseId = treatmentTimerId ?? UUID().uuidString
        let participantName = appData.treatmentTimer?.roomName ?? appData.cycles.last?.patientName ?? "TIPs App"
        
        for i in 0..<4 {
            let content = UNMutableNotificationContent()
            content.title = "\(participantName): Time for the next treatment food"
            content.body = "Your 15 minute treatment food timer has ended."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = "TREATMENT_TIMER"
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "treatment-timer-thread-\(baseId)"
            
            let delay = max(60.0, 1) + Double(i)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: "\(baseId)_repeat_\(i)", content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    // print("Error scheduling notification repeat \(i): \(error.localizedDescription)")
                } else {
                    // print("Scheduled notification repeat \(i) for \(participantName) in \(delay)s, id: \(request.identifier)")
                }
            }
        }
    }
    
    private func observeTimer() {
        NotificationCenter.default.removeObserver(self, name: Notification.Name("ActiveTimerFound"), object: nil)
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ActiveTimerFound"),
            object: nil,
            queue: .main
        ) { notification in
            if let timer = notification.object as? TreatmentTimer {
                // print("ContentView: Received ActiveTimerFound for \(timer.id), remaining: \(timer.endTime.timeIntervalSinceNow)s")
                appData.logToFile("ContentView: Received ActiveTimerFound for \(timer.id), remaining: \(timer.endTime.timeIntervalSinceNow)s")
                
                if timer.isActive && timer.endTime > Date() {
                    DispatchQueue.main.async {
                        self.appData.treatmentTimer = timer
                        self.treatmentTimerId = timer.id
                        self.treatmentCountdowns[timer.id] = timer.endTime.timeIntervalSinceNow
                        self.forceRefreshID = UUID()
                        self.resumeTreatmentTimer()
                        // print("ContentView: Restored timer \(timer.id)")
                        appData.logToFile("ContentView: Restored timer \(timer.id)")
                    }
                } else {
                    // print("ContentView: Ignoring expired timer notification for \(timer.id)")
                    appData.logToFile("ContentView: Ignoring expired timer notification for \(timer.id)")
                    self.stopTreatmentTimer()
                }
            } else {
                // print("ContentView: Received invalid ActiveTimerFound notification")
                appData.logToFile("ContentView: Received invalid ActiveTimerFound notification")
            }
        }
    }
}

struct UserCreationLoadingView: View {
    @ObservedObject var appData: AppData
    @ObservedObject var authViewModel: AuthViewModel
    @State private var timeoutTriggered = false
    
    var body: some View {
        VStack {
            ProgressView("Setting up your account...")
            Text("Please wait...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .onAppear {
            // Only start timeout if not already triggered and not showing name input
            if !timeoutTriggered && !authViewModel.showingNameInput {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    // Only timeout if still in this state, no user created, and not showing name input
                    if !self.timeoutTriggered &&
                       self.appData.currentUser == nil &&
                       !self.authViewModel.showingNameInput &&
                       self.authViewModel.authState == .signedIn {
                        // print("User creation timed out after 8 seconds, signing out")
                        self.timeoutTriggered = true
                        self.authViewModel.signOut()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AuthUserSignedIn"))) { notification in
            // Cancel timeout when user is successfully created
            // print("UserCreationLoadingView: Received AuthUserSignedIn, canceling timeout")
            timeoutTriggered = true
            
            if let userInfo = notification.userInfo,
               let appUser = userInfo["appUser"] as? User {
                // print("UserCreationLoadingView: Setting current user: \(appUser.name)")
                appData.currentUser = appUser
                
                // NEW: Track app version for this user session
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appData.trackAppVersionForCurrentUser()
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(appData: AppData())
            .preferredColorScheme(.dark)
            .environmentObject(AuthViewModel())
    }
}

struct PullToRefresh: View {
    var coordinateSpaceName: String
    var onRefresh: () -> Void
    @Binding var isRefreshing: Bool
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            if offset > 30 && !isRefreshing {
                Spacer()
                    .onAppear {
                        isRefreshing = true
                        onRefresh()
                    }
            }
            
            HStack {
                Spacer()
                VStack {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                            .rotationEffect(.degrees(offset > 15 ? 180 : 0))
                            .animation(.easeInOut, value: offset > 15)
                            .foregroundColor(.secondary)
                        Text(offset > 15 ? "Release to refresh" : "Pull to refresh")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .frame(height: 40)
            .offset(y: -40 + max(offset, 0))
            .onChange(of: geo.frame(in: .named(coordinateSpaceName)).minY) { value in
                offset = value
            }
        }
        .frame(height: 0)
    }
}


