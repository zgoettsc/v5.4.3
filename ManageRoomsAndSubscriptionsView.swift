import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import RevenueCat
import TelemetryDeck

struct ManageRoomsAndSubscriptionsView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var storeManager = StoreManager.shared
    @State private var availableRooms: [String: (String, Bool)] = [:] // [roomId: (name, isOwned)]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingJoinRoom = false
    @State private var showingCreateRoom = false
    @State private var showingSubscriptionView = false
    @State private var currentRoomName: String = "Loading..."
    @State private var isSwitching = false
    @State private var roomToDelete: String? = nil
    @State private var roomToLeave: String? = nil
    @State private var showingDeleteAlert = false
    @State private var showingLeaveAlert = false
    @State private var showingLimitReachedAlert = false
    @State private var selectedPackage: Package?
    @State private var showingPurchaseConfirmation = false
    @State private var showError = false
    @State private var showingSuperAdmin = false
    @State private var showingTransferOwnership = false
    @State private var selectedRoomId: String?
    @State private var selectedRoomName: String?
    @State private var showingSubscriptionPrompt = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss
    
    private var subscriptionPlan: SubscriptionPlan {
        // If in grace period, show no subscription
        if appData.isInGracePeriod {
            return .none
        }
        
        if let plan = appData.currentUser?.subscriptionPlan {
            return SubscriptionPlan(productID: plan)
        }
        return .none
    }
    
    private var roomLimit: Int {
        // If in grace period, show 0 room limit
        if appData.isInGracePeriod {
            return 0
        }
        
        return appData.currentUser?.roomLimit ?? 0
    }
    
    private var ownedRoomCount: Int {
        return appData.currentUser?.ownedRooms?.count ?? 0
    }
    
    private var canCreateRoom: Bool {
        return ownedRoomCount < roomLimit
    }
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Modern Header
                    VStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Rooms and Subscription")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Manage your rooms and subscription settings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Subscription Status Section
                    subscriptionStatusSection
                    
                    // Current Room Section (only if there's a current room)
                    if let roomId = appData.currentRoomId, !roomId.isEmpty {
                        currentRoomSection(roomId: roomId)
                    }
                    
                    // Other Available Rooms
                    otherRoomsSection
                    
                    // Action Buttons
                    actionButtonsSection
                    
                    // Footer Links
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            if isSwitching {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                    Text("Switching Room...")
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                .padding(20)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(10)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentRoomName()
            loadAvailableRooms()
            loadUserSubscriptionStatus()
            storeManager.loadOfferings()
            appData.loadTransferRequests()
        }
        .sheet(isPresented: $showingJoinRoom) {
            JoinRoomView(appData: appData)
                .onDisappear {
                    // Clear all cached data and force refresh
                    availableRooms.removeAll()
                    isLoading = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        loadCurrentRoomName()
                        loadAvailableRooms()
                        loadUserSubscriptionStatus()
                    }
                }
        }
        .sheet(isPresented: $showingCreateRoom) {
            CreateRoomView(appData: appData)
                .environmentObject(authViewModel)
                .onDisappear {
                    loadAvailableRooms()
                }
        }
        .sheet(isPresented: $showingSubscriptionView) {
            NavigationView {
                SubscriptionManagementView(appData: appData)
                    .navigationBarItems(trailing: Button("Done") {
                        showingSubscriptionView = false
                    })
            }
            .onDisappear {
                loadUserSubscriptionStatus()
                loadAvailableRooms()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .confirmationDialog("Confirm Purchase", isPresented: $showingPurchaseConfirmation) {
            Button("Purchase") {
                if let package = selectedPackage {
                    purchasePackage(package)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let package = selectedPackage {
                Text("Purchase \(SubscriptionPlan(productID: package.storeProduct.productIdentifier).displayName) for \(package.localizedPriceString)?")
            }
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Room"),
                message: Text("Are you sure you want to delete this room?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let roomId = roomToDelete {
                        deleteRoom(roomId: roomId)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingLeaveAlert) {
            Alert(
                title: Text("Leave Room"),
                message: Text("Are you sure you want to leave this room? You will no longer have access to the room data."),
                primaryButton: .destructive(Text("Leave")) {
                    if let roomId = roomToLeave {
                        leaveRoom(roomId: roomId)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingLimitReachedAlert) {
            Alert(
                title: Text("Room Limit Reached"),
                message: Text("You have reached the maximum number of rooms allowed in your current subscription plan. Please upgrade your subscription to create more rooms."),
                primaryButton: .default(Text("Upgrade")) {
                    showingSubscriptionView = true
                },
                secondaryButton: .cancel()
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdated"))) { notification in
            print("ManageRoomsView: Received SubscriptionUpdated notification")
            
            // Update local state immediately
            if let userInfo = notification.userInfo,
               let plan = userInfo["plan"] as? String,
               let limit = userInfo["limit"] as? Int,
               let userIdString = userInfo["userIdString"] as? String,
               userIdString == appData.currentUser?.id.uuidString {
                var updatedUser = appData.currentUser
                updatedUser?.subscriptionPlan = plan
                updatedUser?.roomLimit = limit
                appData.currentUser = updatedUser
                appData.objectWillChange.send()
            }
            
            // Fetch latest data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadUserSubscriptionStatus()
                self.loadAvailableRooms()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdateFailed"))) { notification in
            print("ManageRoomsView: Received SubscriptionUpdateFailed notification")
            if let userInfo = notification.userInfo, let error = userInfo["error"] as? String {
                errorMessage = error
                isLoading = false
                showError = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDataRefreshed"))) { _ in
            print("ManageRoomsView: Received UserDataRefreshed notification")
            refreshUserDataFromAppleAuth()  // Use the new method
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RoomLeft"))) { _ in
            loadAvailableRooms()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RoomDeleted"))) { _ in
            loadAvailableRooms()
            loadUserSubscriptionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTransferOwnership"))) { notification in
            if let userInfo = notification.userInfo,
               let roomId = userInfo["roomId"] as? String,
               let roomName = userInfo["roomName"] as? String,
               !roomId.isEmpty {
                print("DEBUG: Setting transfer ownership - roomId: \(roomId), roomName: \(roomName)")
                selectedRoomId = roomId
                selectedRoomName = roomName
                showingTransferOwnership = true
            } else {
                print("DEBUG: Invalid transfer ownership notification data: \(String(describing: notification.userInfo))")
            }
        }
        .sheet(isPresented: $showingSuperAdmin) {
            SuperAdminView(appData: appData)
        }
        .sheet(isPresented: $showingTransferOwnership) {
            if let roomId = selectedRoomId, let roomName = selectedRoomName, !roomId.isEmpty {
                TransferOwnershipView(
                    appData: appData,
                    roomId: roomId,
                    roomName: roomName
                )
            } else {
                VStack {
                    Text("Error: Room information not available")
                    Button("Close") {
                        showingTransferOwnership = false
                    }
                }
                .padding()
            }
        }
        .overlay(
            Group {
                if showingSubscriptionPrompt {
                    SubscriptionPromptView(
                        isPresented: $showingSubscriptionPrompt,
                        onSubscribe: {
                            showingSubscriptionView = true
                        },
                        hasSubscription: subscriptionPlan != .none,
                        isUpgrade: subscriptionPlan != .none && !canCreateRoom
                    )
                }
            }
        )
    }
    // MARK: - View Sections
    
    private var subscriptionStatusSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Subscription Status")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(subscriptionPlan.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "house.fill")
                                .foregroundColor(roomUsageColor)
                                .font(.caption)
                            
                            Text("Rooms: \(ownedRoomCount)/\(roomLimit)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(roomUsageColor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(roomUsageColor.opacity(0.15))
                        )
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingSubscriptionView = true
                    }) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.callout)
                            Text("Manage")
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                
                // Enhanced Progress bar
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: roomLimit > 0 ? (ownedRoomCount >= roomLimit ? [.orange, .red] : [.blue, .purple]) : [.gray]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: roomLimit > 0 ? min(CGFloat(ownedRoomCount) / CGFloat(roomLimit) * geometry.size.width, geometry.size.width) : 0, height: 12)
                        }
                    }
                    .frame(height: 12)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }
    
    private var roomUsageColor: Color {
        if roomLimit == 0 { return .gray }
        return ownedRoomCount >= roomLimit ? .orange : .green
    }
    
    private func currentRoomSection(roomId: String) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Current Room")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            let isOwned = appData.currentUser?.ownedRooms?.contains(roomId) ?? false
            
            VStack(spacing: 12) {
                RoomEntryView(roomId: roomId, roomName: currentRoomName, appData: appData)
                    .padding(20)
                    .background(Color.clear)
                
                // Enhanced Status indicators
                HStack {
                    HStack(spacing: 6) {
                        let isSuperAdmin = appData.currentUser?.isSuperAdmin == true
                        
                        if isSuperAdmin && !isOwned {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            
                            Text("Super Admin")
                                .font(.caption)
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: isOwned ? "crown.fill" : "person.fill")
                                .font(.caption2)
                                .foregroundColor(isOwned ? .yellow : .orange)
                            
                            Text(isOwned ? "Owner" : "Invited")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(appData.currentUser?.isSuperAdmin == true && !isOwned ? Color.purple.opacity(0.15) : (isOwned ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15)))
                    )
                    .foregroundColor(appData.currentUser?.isSuperAdmin == true && !isOwned ? .purple : (isOwned ? .blue : .orange))
                    
                    // Grace period indicator for owned rooms
                    if isOwned && appData.isInGracePeriod, let gracePeriodEnd = appData.subscriptionGracePeriodEnd {
                        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
                        
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("\(daysRemaining)d left")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.15))
                        )
                        .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
                    .foregroundColor(.green)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.5), lineWidth: 2)
                    )
                    .shadow(color: .green.opacity(0.1), radius: 8, x: 0, y: 2)
            )
        }
    }
    
    private var otherRoomsSection: some View {
        Group {
            if !availableRooms.filter({ $0.key != appData.currentRoomId }).isEmpty {
                VStack(spacing: 20) {
                    HStack {
                        Text("Other Rooms")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    LazyVStack(spacing: 16) {
                        ForEach(Array(availableRooms.keys.sorted()), id: \.self) { roomId in
                            if roomId != appData.currentRoomId {
                                let roomInfo = availableRooms[roomId]!
                                let roomName = roomInfo.0
                                let isOwned = roomInfo.1
                                
                                VStack(spacing: 12) {
                                    RoomEntryView(roomId: roomId, roomName: roomName, appData: appData)
                                        .padding(20)
                                        .background(Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            switchToRoom(roomId: roomId)
                                        }
                                    
                                    // Enhanced Status indicators
                                    HStack {
                                        HStack(spacing: 6) {
                                            let isSuperAdmin = appData.currentUser?.isSuperAdmin == true
                                            
                                            if isSuperAdmin && !isOwned {
                                                Image(systemName: "crown.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.purple)
                                                
                                                Text("Super Admin")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            } else {
                                                Image(systemName: isOwned ? "crown.fill" : "person.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(isOwned ? .yellow : .orange)
                                                
                                                Text(isOwned ? "Owner" : "Invited")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(appData.currentUser?.isSuperAdmin == true && !isOwned ? Color.purple.opacity(0.15) : (isOwned ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15)))
                                        )
                                        .foregroundColor(appData.currentUser?.isSuperAdmin == true && !isOwned ? .purple : (isOwned ? .blue : .orange))
                                        
                                        // Grace period indicator for owned rooms
                                        if isOwned && appData.isInGracePeriod, let gracePeriodEnd = appData.subscriptionGracePeriodEnd {
                                            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: gracePeriodEnd).day ?? 0
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                Text("\(daysRemaining)d left")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.red.opacity(0.15))
                                            )
                                            .foregroundColor(.red)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.secondarySystemBackground))
                                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var actionButtonsSection: some View {
            VStack(spacing: 16) {
                Button(action: {
                    if canCreateRoom {
                        showingCreateRoom = true
                    } else {
                        showingSubscriptionPrompt = true
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.headline)
                        Text("Create New Room")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                Button(action: {
                    showingJoinRoom = true
                }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                        Text("Join Room with Invite Code")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.purple, .purple.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
        }
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                Button("Privacy Policy & User Agreement") {
                    if let url = URL(string: "https://www.zthreesolutions.com/privacy-policy-user-agreement") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                
                Button("Terms of Service (EULA)") {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            // Super Admin Access (discrete)
            Button(action: {
                // Add TelemetryDeck signal
                TelemetryDeck.signal("developer_access_button_clicked")
                showingSuperAdmin = true
            }) {
                Text("•")
                    .font(.title2)
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentRoomName() {
        guard let roomId = appData.currentRoomId else {
            currentRoomName = "No room selected"
            return
        }
        
        loadRoomName(roomId: roomId) { name in
            if let name = name {
                self.currentRoomName = name
            } else {
                self.currentRoomName = "Room \(roomId.prefix(6))"
            }
        }
    }
    
    private func loadRoomName(roomId: String, completion: @escaping (String?) -> Void) {
        let dbRef = Database.database().reference()
        
        // Force fresh data by using observeSingleEvent with no caching
        dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value, with: { snapshot in
            // Double check the room still exists
            guard snapshot.exists() else {
                completion("Deleted Room")
                return
            }
            
            if let roomData = snapshot.value as? [String: Any] {
                if let cycles = roomData["cycles"] as? [String: [String: Any]] {
                    var latestCycle: [String: Any]? = nil
                    var latestStartDate: Date? = nil
                    
                    for (_, cycleData) in cycles {
                        if let startDateStr = cycleData["startDate"] as? String,
                           let startDate = ISO8601DateFormatter().date(from: startDateStr) {
                            if latestStartDate == nil || startDate > latestStartDate! {
                                latestStartDate = startDate
                                latestCycle = cycleData
                            }
                        }
                    }
                    
                    if let latestCycle = latestCycle,
                       let patientName = latestCycle["patientName"] as? String,
                       !patientName.isEmpty && patientName != "Unnamed" {
                        completion("\(patientName)'s Program")
                        return
                    }
                    
                    for (_, cycleData) in cycles {
                        if let patientName = cycleData["patientName"] as? String,
                           !patientName.isEmpty && patientName != "Unnamed" {
                            completion("\(patientName)'s Program")
                            return
                        }
                    }
                }
                
                if let roomName = roomData["name"] as? String {
                    completion(roomName)
                    return
                }
            }
            completion("Room \(roomId.prefix(8))")
        }) { error in
            print("Error loading room name for \(roomId): \(error)")
            completion("Room \(roomId.prefix(8))")
        }
    }
    
    private func refreshUserDataFromAppleAuth() {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        
        // Get Apple ID from provider data
        var appleId: String?
        for provider in firebaseUser.providerData {
            if provider.providerID == "apple.com" {
                appleId = provider.uid
                break
            }
        }
        
        guard let appleUserId = appleId else {
            print("No Apple ID found for user refresh")
            return
        }
        
        // ENCODE the Apple ID for Firebase safety
        let encodedAppleId = encodeForFirebase(appleUserId)
        print("Refreshing user data for encoded Apple ID: \(encodedAppleId)")
        
        let dbRef = Database.database().reference()
        dbRef.child("auth_mapping").child(encodedAppleId).observeSingleEvent(of: .value) { snapshot in
            guard let userIdString = snapshot.value as? String else {
                print("No mapping found for Apple ID: \(encodedAppleId)")
                return
            }
            
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                if let userData = userSnapshot.value as? [String: Any] {
                    var userDict = userData
                    userDict["id"] = userIdString
                    
                    if let user = User(dictionary: userDict) {
                        DispatchQueue.main.async {
                            self.appData.currentUser = user
                            self.loadAvailableRooms()
                            self.loadUserSubscriptionStatus()
                        }
                    }
                }
            }
        }
    }

    // Add this helper method at the bottom of ManageRoomsAndSubscriptionsView
    private func encodeForFirebase(_ string: String) -> String {
        return string
            .replacingOccurrences(of: ".", with: "_DOT_")
            .replacingOccurrences(of: "#", with: "_HASH_")
            .replacingOccurrences(of: "$", with: "_DOLLAR_")
            .replacingOccurrences(of: "[", with: "_LBRACKET_")
            .replacingOccurrences(of: "]", with: "_RBRACKET_")
    }
    
    private func loadAvailableRooms() {
        guard let user = appData.currentUser else {
            errorMessage = "User not found"
            isLoading = false
            return
        }
        
        let userId = user.id.uuidString
        isLoading = true
        
        // Force refresh user data first to get updated roomAccess
        let dbRef = Database.database().reference()
        
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
            guard let userData = snapshot.value as? [String: Any] else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not load user data"
                    self.isLoading = false
                }
                return
            }
            
            // Update current user with fresh data
            var updatedUser = user
            updatedUser.ownedRooms = userData["ownedRooms"] as? [String]
            updatedUser.subscriptionPlan = userData["subscriptionPlan"] as? String
            updatedUser.roomLimit = userData["roomLimit"] as? Int ?? 0
            
            DispatchQueue.main.async {
                self.appData.currentUser = updatedUser
            }
            
            var rooms: [String: (String, Bool)] = [:]
            let userOwnedRooms = updatedUser.ownedRooms ?? []
            let dispatchGroup = DispatchGroup()
            
            // Load room access information with fresh data
            if let roomAccess = userData["roomAccess"] as? [String: Any] {
                for (roomId, _) in roomAccess {
                    dispatchGroup.enter()
                    self.loadRoomName(roomId: roomId) { roomName in
                        let isOwned = userOwnedRooms.contains(roomId)
                        rooms[roomId] = (roomName ?? "Room \(roomId.prefix(6))", isOwned)
                        dispatchGroup.leave()
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                self.availableRooms = rooms
                self.isLoading = false
            }
        }
    }
    
    func loadUserSubscriptionStatus() {
        let dbRef = Database.database().reference()
        
        guard let user = appData.currentUser else {
            return
        }
        
        let userId = user.id.uuidString
        
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
            if let userData = snapshot.value as? [String: Any] {
                var updatedUser = user
                updatedUser.subscriptionPlan = userData["subscriptionPlan"] as? String
                updatedUser.roomLimit = userData["roomLimit"] as? Int ?? 0
                updatedUser.ownedRooms = userData["ownedRooms"] as? [String]
                
                DispatchQueue.main.async {
                    self.appData.currentUser = updatedUser
                    self.loadAvailableRooms()
                }
            }
        }
    }
    
    private func switchToRoom(roomId: String) {
        isSwitching = true
        
        appData.switchToRoom(roomId: roomId)
        
        // Allow some time for the switch to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isSwitching = false
            loadCurrentRoomName()
            loadAvailableRooms()
            
            // If in settings, dismiss this view and navigate to home
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: Notification.Name("NavigateToHomeTab"), object: nil)
                self.dismiss()
            }
        }
    }
    
    private func leaveRoom(roomId: String) {
        appData.leaveRoom(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Clear cached room data first
                    self.availableRooms.removeAll()
                    self.currentRoomName = "Loading..."
                    
                    // Force the view to show loading state
                    self.isLoading = true
                    
                    // Small delay to ensure Firebase operations complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Force refresh all room data
                        self.loadCurrentRoomName()
                        self.loadAvailableRooms()
                        self.loadUserSubscriptionStatus()
                    }
                    
                    // Clear any error messages
                    self.errorMessage = nil
                } else if let error = error {
                    self.errorMessage = error
                    self.showError = true
                }
            }
        }
    }
    
    private func deleteRoom(roomId: String) {
        guard let ownedRooms = appData.currentUser?.ownedRooms,
              ownedRooms.contains(roomId) else {
            errorMessage = "You can only delete rooms you have created"
            showError = true
            return
        }
        
        appData.deleteRoom(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Clear cached room data first
                    self.availableRooms.removeAll()
                    self.currentRoomName = "Loading..."
                    
                    // Force the view to show loading state
                    self.isLoading = true
                    
                    // Small delay to ensure Firebase operations complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Force refresh all room data
                        self.loadCurrentRoomName()
                        self.loadAvailableRooms()
                        self.loadUserSubscriptionStatus()
                    }
                    
                    // Clear any error messages
                    self.errorMessage = nil
                } else if let error = error {
                    self.errorMessage = error
                    self.showError = true
                }
            }
        }
    }
    
    private func purchasePackage(_ package: Package) {
        storeManager.purchasePackage(package, appData: appData) { success, error in
            if success {
                // UI will be updated via notification, no need for additional delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Just a small delay to ensure notification propagates
                }
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
}
