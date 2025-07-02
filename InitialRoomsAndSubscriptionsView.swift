//
//  InitialRoomsAndSubscriptionsView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/10/25.
//


import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import TelemetryDeck

struct InitialRoomsAndSubscriptionsView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var availableRooms: [String: (String, Bool)] = [:] // [roomId: (name, isOwned)]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingJoinRoom = false
    @State private var showingCreateRoom = false
    @State private var showingSubscriptionView = false
    @State private var isSwitching = false
    @State private var roomToDelete: String? = nil
    @State private var roomToLeave: String? = nil
    @State private var showingDeleteAlert = false
    @State private var showingLeaveAlert = false
    @State private var showingLimitReachedAlert = false
    @State private var showingSignOutAlert = false
    @State private var showOnboarding = false
    @State private var showingSuperAdmin = false
    @State private var showingTransferOwnership = false
    @State private var selectedRoomId: String?
    @State private var selectedRoomName: String?
    @State private var showingSubscriptionPrompt = false
    @Environment(\.colorScheme) private var colorScheme
    
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
                        
                        Text("Select a Room")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Choose a room to enter or create a new one")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Subscription Status
                    subscriptionStatusSection
                    
                    // Available Rooms Section
                    availableRoomsSection
                    
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
                    Text("Entering Room...")
                        .foregroundColor(.white)
                        .padding(.top, 10)
                }
                .padding(20)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(10)
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear(perform: onAppearSetup)
        .onAppear {
            // existing onAppear code...
            appData.loadTransferRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdated"))) { notification in
            print("InitialRoomsView: Received SubscriptionUpdated notification")
            
            // Update local state immediately if userInfo contains the data
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
                print("InitialRoomsView: Updated UI with new subscription: \(plan)")
            }
            
            // No need for additional fetch since we updated immediately
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdateFailed"))) { notification in
            print("InitialRoomsView: Received SubscriptionUpdateFailed notification")
            if let userInfo = notification.userInfo, let error = userInfo["error"] as? String {
                errorMessage = error
                isLoading = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDataRefreshed"))) { _ in
            print("InitialRoomsView: Received UserDataRefreshed notification")
            loadUserSubscriptionStatus()
            loadAvailableRooms()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTransferOwnership"))) { notification in
            if let userInfo = notification.userInfo,
               let roomId = userInfo["roomId"] as? String,
               let roomName = userInfo["roomName"] as? String {
                selectedRoomId = roomId
                selectedRoomName = roomName
                showingTransferOwnership = true
            }
        }
        .sheet(isPresented: $showingJoinRoom) {
            JoinRoomView(appData: appData)
                .onDisappear {
                    // Clear all cached data and force refresh
                    availableRooms.removeAll()
                    isLoading = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
        .sheet(isPresented: $showingSuperAdmin) {
            SuperAdminView(appData: appData)
        }
        .sheet(isPresented: $showingTransferOwnership) {
            if let roomId = selectedRoomId, let roomName = selectedRoomName {
                TransferOwnershipView(
                    appData: appData,
                    roomId: roomId,
                    roomName: roomName
                )
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isShowingOnboarding: $showOnboarding)
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
        .alert(isPresented: $showingSignOutAlert) {
            Alert(
                title: Text("Sign Out"),
                message: Text("Are you sure you want to sign out?"),
                primaryButton: .destructive(Text("Sign Out")) {
                    signOut()
                },
                secondaryButton: .cancel()
            )
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
    
    private var availableRoomsSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Available Rooms")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading rooms...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
            } else if availableRooms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "house")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("No rooms available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(availableRooms.keys.sorted()), id: \.self) { roomId in
                        let roomInfo = availableRooms[roomId]!
                        let roomName = roomInfo.0
                        let isOwned = roomInfo.1
                        
                        VStack(spacing: 12) {
                            RoomEntryView(roomId: roomId, roomName: roomName, appData: appData)
                                .padding(20)
                                .background(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    enterRoom(roomId: roomId)
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
                
                // Sign Out Button
                Button(action: {
                    showingSignOutAlert = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                        Text("Sign Out")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.red.opacity(0.8), .red.opacity(0.6)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
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
    
    // MARK: - All existing methods remain unchanged
    
    private func onAppearSetup() {
        isLoading = true
        errorMessage = nil
        
        // DON'T SHOW ONBOARDING HERE - wait until after login
        
        // Add listener for when auth user signs in
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AuthUserSignedIn"),
            object: nil,
            queue: .main
        ) { notification in
            // Check if we have the app user in the notification
            if let userInfo = notification.userInfo,
               let appUser = userInfo["appUser"] as? User {
                // We already have the user, just set it
                self.appData.currentUser = appUser
                self.loadUserSubscriptionStatus()
                self.loadAvailableRooms()
                
                // NOW CHECK FOR ONBOARDING AFTER SUCCESSFUL LOGIN
                if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.showOnboarding = true
                    }
                }
            } else {
                // Give a short delay for Firebase operations to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.fetchUserData()
                }
            }
        }
        
        // Check if we already have an authenticated user
        if let currentUser = Auth.auth().currentUser {
            print("Firebase Auth user is logged in: \(currentUser.uid)")
            
            // If we already have appData.currentUser, just load data
            if appData.currentUser != nil {
                loadUserSubscriptionStatus()
                loadAvailableRooms()
            } else {
                // Give a delay for new signups to complete Firebase setup
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.fetchUserData()
                }
            }
        } else {
            print("No Firebase Auth user logged in")
            isLoading = false
            errorMessage = "Not logged in"
        }
        checkAndShowOnboarding()
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
            
            print("Loading rooms for user: \(userId)")
            print("User has \(userOwnedRooms.count) owned rooms")
            
            // Load room access information with fresh data
            if let roomAccess = userData["roomAccess"] as? [String: Any] {
                print("Found \(roomAccess.count) rooms in roomAccess")
                for (roomId, _) in roomAccess {
                    dispatchGroup.enter()
                    self.loadRoomName(roomId: roomId) { roomName in
                        let isOwned = userOwnedRooms.contains(roomId)
                        rooms[roomId] = (roomName ?? "Room \(roomId.prefix(6))", isOwned)
                        print("Added room: \(roomId) with name: \(roomName ?? "unknown")")
                        dispatchGroup.leave()
                    }
                }
            } else {
                print("No roomAccess found for user")
            }
            
            dispatchGroup.notify(queue: .main) {
                print("Found total of \(rooms.count) rooms for user")
                self.availableRooms = rooms
                self.isLoading = false
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
    
    func loadUserSubscriptionStatus() {
        print("InitialRoomsView: Loading subscription status")
        guard let user = appData.currentUser else {
            print("InitialRoomsView: No current user found")
            return
        }
        
        let userId = user.id.uuidString
        let dbRef = Database.database().reference()
        
        print("InitialRoomsView: Loading subscription status for user \(userId)")
        
        // Use direct string instead of checking optionality
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot, _ in
            if let userData = snapshot.value as? [String: Any] {
                var updatedUser = user
                
                // Extract subscription data
                let subscriptionPlan = userData["subscriptionPlan"] as? String
                let roomLimit = userData["roomLimit"] as? Int ?? 0
                let ownedRooms = userData["ownedRooms"] as? [String]
                
                print("InitialRoomsView: Loaded subscription data - plan: \(subscriptionPlan ?? "none"), limit: \(roomLimit)")
                
                updatedUser.subscriptionPlan = subscriptionPlan
                updatedUser.roomLimit = roomLimit
                updatedUser.ownedRooms = ownedRooms
                
                DispatchQueue.main.async {
                    self.appData.currentUser = updatedUser
                    print("InitialRoomsView: Updated current user with subscription data")
                    self.loadAvailableRooms()
                }
            } else {
                print("InitialRoomsView: No user data found for ID: \(userId)")
            }
        }
    }
    
    private func checkAndShowOnboarding() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.showOnboarding = true
        }
    }
    
    private func enterRoom(roomId: String) {
        guard let currentUser = appData.currentUser else {
            errorMessage = "No current user found"
            return
        }
        
        isSwitching = true
        
        // Check if user needs migration to new structure
        if currentUser.roomAccess == nil || currentUser.roomSettings == nil {
            print("User needs migration to new structure")
            
            // Set the room ID first so migration can use it
            UserDefaults.standard.set(roomId, forKey: "currentRoomId")
            
            // Migrate user to new structure
            appData.migrateUserToNewStructure(user: currentUser) { migratedUser in
                DispatchQueue.main.async {
                    if let migratedUser = migratedUser {
                        print("User migration completed successfully")
                        self.appData.currentUser = migratedUser
                        self.appData.switchToRoom(roomId: roomId)
                        
                        // Post notification to navigate to home tab
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(name: Notification.Name("NavigateToHomeTab"), object: nil)
                        }
                    } else {
                        print("User migration failed")
                        self.errorMessage = "Failed to migrate user data. Please try again."
                        self.isSwitching = false
                    }
                }
            }
        } else {
            // User already has new structure, proceed normally
            print("User already has new structure, proceeding normally")
            appData.switchToRoom(roomId: roomId)
            
            // Post notification to navigate to home tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: Notification.Name("NavigateToHomeTab"), object: nil)
            }
        }
    }
    
    private func leaveRoom(roomId: String) {
        appData.leaveRoom(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Clear cached room data first
                    self.availableRooms.removeAll()
                    
                    // Force the view to show loading state
                    self.isLoading = true
                    
                    // Small delay to ensure Firebase operations complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Force refresh all room data
                        self.loadAvailableRooms()
                        self.loadUserSubscriptionStatus()
                    }
                    
                    // Clear any error messages
                    self.errorMessage = nil
                } else if let error = error {
                    self.errorMessage = error
                }
            }
        }
    }
    
    private func deleteRoom(roomId: String) {
        // First check if this is a room the user owns
        guard let ownedRooms = appData.currentUser?.ownedRooms,
              ownedRooms.contains(roomId) else {
            errorMessage = "You can only delete rooms you have created"
            return
        }
        
        // Delete the room
        appData.deleteRoom(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Clear cached room data first
                    self.availableRooms.removeAll()
                    
                    // Force the view to show loading state
                    self.isLoading = true
                    
                    // Small delay to ensure Firebase operations complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Force refresh all room data
                        self.loadAvailableRooms()
                        self.loadUserSubscriptionStatus()
                    }
                    
                    // Clear any error messages
                    self.errorMessage = nil
                } else if let error = error {
                    self.errorMessage = error
                }
            }
        }
    }
    
    func fetchUserData() {
        guard let currentUser = Auth.auth().currentUser else {
            print("No Firebase Auth user logged in")
            isLoading = false
            errorMessage = "Not logged in"
            return
        }
        
        print("Fetching user data for auth ID: \(currentUser.uid)")
        let dbRef = Database.database().reference()
        
        // First check if user mapping exists with retry logic
        func checkAuthMapping(attempt: Int = 0) {
            // For Apple Sign In, we need to get the Apple ID from the current Firebase user
            // The Firebase user's providerData will contain the Apple provider info
            var appleId: String?
            
            for provider in currentUser.providerData {
                if provider.providerID == "apple.com" {
                    appleId = provider.uid // This is the Apple user ID
                    break
                }
            }
            
            guard let appleUserId = appleId else {
                print("No Apple ID found in user provider data")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Apple ID not found. Please contact support."
                }
                return
            }
            
            print("Using Apple ID for lookup: \(appleUserId)")
            
            // ENCODE THE APPLE ID FOR FIREBASE SAFETY
            let encodedAppleId = encodeForFirebase(appleUserId)
            print("Encoded Apple ID: \(encodedAppleId)")
            
            dbRef.child("auth_mapping").child(encodedAppleId).observeSingleEvent(of: .value) { snapshot, _ in
                if let userIdString = snapshot.value as? String {
                    print("Found user mapping: \(userIdString)")
                    
                    // Load user data from Firebase
                    dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot, _ in
                        if let userData = userSnapshot.value as? [String: Any] {
                            print("Found user data: \(userData)")
                            
                            // Create User object with necessary fields
                            var userDict = userData
                            userDict["id"] = userIdString
                            
                            // Set a default name if not present (needed by the User initializer)
                            if userDict["name"] == nil {
                                userDict["name"] = currentUser.displayName ?? "User"
                            }
                            
                            if let user = User(dictionary: userDict) {
                                DispatchQueue.main.async {
                                    self.appData.currentUser = user
                                    
                                    // Save to UserDefaults
                                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                                    print("Successfully loaded user: \(user.name), plan: \(user.subscriptionPlan ?? "none"), limit: \(user.roomLimit)")
                                    
                                    // Refresh available rooms
                                    self.loadAvailableRooms()
                                    self.loadUserSubscriptionStatus()
                                    self.isLoading = false
                                    self.errorMessage = nil
                                }
                            } else {
                                print("Failed to parse user data")
                                
                                // Create a minimal User object directly
                                let user = User(
                                    id: UUID(uuidString: userIdString) ?? UUID(),
                                    name: currentUser.displayName ?? "User",
                                    authId: appleUserId, // Use Apple ID
                                    ownedRooms: userData["ownedRooms"] as? [String],
                                    subscriptionPlan: userData["subscriptionPlan"] as? String,
                                    roomLimit: userData["roomLimit"] as? Int ?? 0,
                                    isSuperAdmin: userData["isSuperAdmin"] as? Bool ?? false
                                )
                                
                                DispatchQueue.main.async {
                                    self.appData.currentUser = user
                                    
                                    // Save to UserDefaults
                                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                                    print("Created new user object: \(user.name)")
                                    
                                    // Save the user to Firebase to update it with required fields
                                    self.appData.addUser(user)
                                    
                                    // Refresh available rooms
                                    self.loadAvailableRooms()
                                    self.loadUserSubscriptionStatus()
                                    self.isLoading = false
                                    self.errorMessage = nil
                                }
                            }
                        } else {
                            print("No user data found for ID: \(userIdString)")
                            
                            // Create a new user if none exists
                            let newUser = User(
                                id: UUID(uuidString: userIdString) ?? UUID(),
                                name: currentUser.displayName ?? "User",
                                authId: appleUserId // Use Apple ID
                            )
                            
                            DispatchQueue.main.async {
                                self.appData.currentUser = newUser
                                
                                // Save to UserDefaults
                                UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                                print("Created brand new user: \(newUser.name)")
                                
                                // Save the user to Firebase
                                self.appData.addUser(newUser)
                                
                                self.loadAvailableRooms()
                                self.loadUserSubscriptionStatus()
                                self.isLoading = false
                                self.errorMessage = nil
                            }
                        }
                    }
                } else {
                    print("No user mapping found for Apple ID: \(appleUserId)")
                    
                    // Retry up to 3 times with increasing delays for new signups
                    if attempt < 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt + 1)) {
                            checkAuthMapping(attempt: attempt + 1)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.errorMessage = "User not found in database. Please contact support."
                        }
                    }
                }
            }
        }
        
        checkAuthMapping()
    }

    // Add this helper method to InitialRoomsAndSubscriptionsView
    private func encodeForFirebase(_ string: String) -> String {
        return string
            .replacingOccurrences(of: ".", with: "_DOT_")
            .replacingOccurrences(of: "#", with: "_HASH_")
            .replacingOccurrences(of: "$", with: "_DOLLAR_")
            .replacingOccurrences(of: "[", with: "_LBRACKET_")
            .replacingOccurrences(of: "]", with: "_RBRACKET_")
    }
    
    private func signOut() {
        // Sign out from Firebase Auth
        do {
            try Auth.auth().signOut()
            
            // Clear local app state
            appData.currentUser = nil
            appData.currentRoomId = nil
            
            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: "currentUserId")
            UserDefaults.standard.removeObject(forKey: "currentRoomId")
            
            // Post notification about user sign out
            NotificationCenter.default.post(name: Notification.Name("UserDidSignOut"), object: nil)
        } catch {
            errorMessage = "Error signing out: \(error.localizedDescription)"
        }
    }
}
