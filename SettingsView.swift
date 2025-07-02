import SwiftUI
import TelemetryDeck
import FirebaseDatabase

struct SettingsView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingRoomCodeSheet = false
    @State private var newRoomCode = ""
    @State private var showingConfirmation = false
    @State private var showingShareSheet = false
    @State private var selectedUser: User?
    @State private var showingEditNameSheet = false
    @State private var editedName = ""
    @State private var showingDeleteAccountAlert = false
    @State private var showingAccountErrorAlert = false
    @State private var accountErrorMessage = ""
    @State private var showingOnboardingTutorial = false
    @State private var showingTransferDebug = false
    @StateObject private var versionManager = AppVersionManager()
    
    // Helper function to calculate days until food challenge
    private var daysUntilFoodChallenge: String {
        guard let cycle = appData.cycles.first else {
            return "No cycle available"
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: cycle.foodChallengeDate)
        if let days = components.day {
            return days >= 0 ? "\(days) day\(days == 1 ? "" : "s") remaining" : "Food challenge date passed"
        }
        return "Unknown"
    }
    
    private var currentRoomId: String? {
        UserDefaults.standard.string(forKey: "currentRoomId")
    }
    
    var body: some View {
        List {
            // App Version Section
            Section(header: Text("APP VERSION")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Current Version")
                            .font(.headline)
                        Spacer()
                        Text("v\(versionManager.currentVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if versionManager.hasUpdate {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Update Available")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("v\(versionManager.latestVersion)")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        
                        Button(action: {
                            versionManager.openAppStore()
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.white)
                                Text("Update Now")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Food Challenge Date Section (Informational)
            Section(header: Text("FOOD CHALLENGE")) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Days until Food Challenge")
                            .font(.headline)
                        Text(daysUntilFoodChallenge)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // Rooms, Users, Subscriptions Section
            Section(header: Text("ROOMS, USERS, SUBSCRIPTIONS")) {
                NavigationLink(destination: ManageRoomsAndSubscriptionsView(appData: appData)) {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.teal)
                        Text("Rooms and Subscriptions")
                            .font(.headline)
                    }
                }
                NavigationLink(destination: TransferRequestsView(appData: appData)) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.purple)
                        Text("Room Transfer Requests")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Show badge if there are pending requests
                        if !appData.transferRequests.isEmpty {
                            Text("\(appData.transferRequests.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }
                }
                
                if let roomId = currentRoomId,
                   (appData.currentUser?.roomAccess?[roomId]?.isAdmin ?? false) ||
                   (appData.currentUser?.isSuperAdmin ?? false) {
                    NavigationLink(destination: UserManagementView(appData: appData)) {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.purple)
                            Text("Invite & Manage Room Users")
                                .font(.headline)
                        }
                    }
                }
            }
            
            // Plan Management Section
            Section(header: Text("PLAN MANAGEMENT")) {
                if (appData.currentUser?.roomAccess?[UserDefaults.standard.string(forKey: "currentRoomId") ?? ""]?.isAdmin ?? false) ||
                   (appData.currentUser?.isSuperAdmin ?? false) {
                    NavigationLink(destination: EditPlanView(appData: appData)) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.blue)
                            Text("Edit Plan")
                                .font(.headline)
                        }
                    }
                }
                
                NavigationLink(destination: NotificationsView(appData: appData)) {
                    HStack {
                        Image(systemName: "bell")
                            .foregroundColor(.orange)
                        Text("Notifications")
                            .font(.headline)
                    }
                }
                
                NavigationLink(destination: HistoryView(appData: appData)) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.green)
                        Text("History")
                            .font(.headline)
                    }
                }
                
                NavigationLink(destination: ReactionsView(appData: appData)) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Reactions")
                            .font(.headline)
                    }
                }
                
                // Missed Doses
                if let roomId = currentRoomId,
                   (appData.currentUser?.roomAccess?[roomId]?.isAdmin ?? false) ||
                   (appData.currentUser?.isSuperAdmin ?? false) {
                    NavigationLink(destination: MissedDoseManagementView(appData: appData)) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Manage Missed Doses")
                                .font(.headline)
                        }
                    }
                }
                
                NavigationLink(destination: ContactTIPsView()) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.indigo)
                        Text("Contact TIPs")
                            .font(.headline)
                    }
                }
                
                Button(action: {
                    showingOnboardingTutorial = true
                }) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.teal)
                        Text("App Tutorial")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // Account Section
            Section(header: Text("ACCOUNT")) {
                NavigationLink(destination: AccountManagementView(appData: appData)) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                        Text("Account Management")
                            .font(.headline)
                    }
                }
            }
            // Section(header: Text("DEBUG TRANSFER REQUESTS")) {
            //     Button("Debug Transfer Requests") {
            //         debugTransferRequests()
            //     }
            //     .foregroundColor(.purple)
            //
            //     if let currentUser = appData.currentUser {
            //         Text("User: \(currentUser.name)")
            //             .font(.caption)
            //         Text("ID: \(currentUser.id.uuidString)")
            //             .font(.caption)
            //         Text("Pending Requests: \(currentUser.pendingTransferRequests?.count ?? 0)")
            //             .font(.caption)
            //         if let requests = currentUser.pendingTransferRequests {
            //             ForEach(requests, id: \.self) { requestId in
            //                 Text("Request: \(requestId)")
            //                     .font(.caption2)
            //             }
            //         }
            //     }
            //     Button("Clean Up Transfer Requests") {
            //         appData.cleanupDanglingTransferRequests {
            //             print("DEBUG: Cleanup completed")
            //         }
            //     }
            //     .padding()
            //     .background(Color.blue)
            //     .foregroundColor(.white)
            //     .cornerRadius(8)
            // }
            
            // Developer Section (only for super admins)
            if appData.currentUser?.isSuperAdmin == true {
                Section(header: Text("DEVELOPER")) {
                    NavigationLink(destination: DeveloperSettingsView(appData: appData)) {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(.orange)
                            Text("Developer Tools")
                                .font(.headline)
                        }
                    }
                    .onTapGesture {
                        TelemetryDeck.signal("developer_settings_accessed")
                    }
                }
            }
            
            // Legal Section
            Section(header: Text("LEGAL")) {
                Link(destination: URL(string: "https://www.zthreesolutions.com/privacy-policy-user-agreement")!) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.blue)
                        Text("Privacy Policy & User Agreement")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("Terms of Use (EULA)")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingEditNameSheet) {
            NavigationView {
                Form {
                    TextField("Your Name", text: $editedName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .navigationTitle("Edit Your Name")
                .navigationBarItems(
                    leading: Button("Cancel") { showingEditNameSheet = false },
                    trailing: Button("Save") {
                        if let user = appData.currentUser, !editedName.isEmpty {
                            let updatedUser = User(
                                id: user.id,
                                name: editedName,
                                authId: user.authId,
                                ownedRooms: user.ownedRooms,
                                subscriptionPlan: user.subscriptionPlan,
                                roomLimit: user.roomLimit,
                                isSuperAdmin: user.isSuperAdmin,
                                pendingTransferRequests: user.pendingTransferRequests,
                                roomAccess: user.roomAccess,
                                roomSettings: user.roomSettings
                            )
                            appData.addUser(updatedUser)
                            if appData.currentUser?.id == user.id {
                                appData.currentUser = updatedUser
                            }
                        }
                        showingEditNameSheet = false
                    }
                        .disabled(editedName.isEmpty)
                )
            }
        }
        .sheet(isPresented: $showingOnboardingTutorial) {
            OnboardingView(isShowingOnboarding: $showingOnboardingTutorial)
        }
        .onAppear {
            // Force refresh user data to ensure isSuperAdmin is current
            appData.forceRefreshCurrentUser()
            print("SettingsView - Current user isSuperAdmin: \(appData.currentUser?.isSuperAdmin ?? false)")
            
            // Auto-check for updates when settings loads
            versionManager.checkForUpdate()
            
            // Listen for transfer request notifications
            NotificationCenter.default.addObserver(
                forName: Notification.Name("TransferRequestReceived"),
                object: nil,
                queue: .main
            ) { notification in
                print("DEBUG: SettingsView received TransferRequestReceived notification")
                
                // If this is for the current user, refresh their transfer requests
                if let userInfo = notification.userInfo,
                   let ownerId = userInfo["ownerId"] as? String,
                   ownerId == appData.currentUser?.id.uuidString {
                    print("DEBUG: This notification is for current user, refreshing transfer requests")
                    
                    // Force refresh the current user's data
                    appData.forceRefreshCurrentUser {
                        // Then load transfer requests
                        appData.loadTransferRequests()
                    }
                }
            }
            
            // Listen for navigation to transfer requests
            NotificationCenter.default.addObserver(
                forName: Notification.Name("NavigateToTransferRequests"),
                object: nil,
                queue: .main
            ) { _ in
                // Could trigger navigation to TransferRequestsView if needed
                // For now, the user can find it in the existing UI
            }
        }
    }
    // private func debugTransferRequests() {
    //     guard let currentUser = appData.currentUser else {
    //         print("DEBUG: No current user")
    //         return
    //     }
    //
    //     print("DEBUG: Current user: \(currentUser.name) (\(currentUser.id.uuidString))")
    //     print("DEBUG: Pending requests in user object: \(currentUser.pendingTransferRequests?.count ?? 0)")
    //
    //     let dbRef = Database.database().reference()
    //
    //     // Check user's pending requests in Firebase
    //     dbRef.child("users").child(currentUser.id.uuidString).child("pendingTransferRequests").observeSingleEvent(of: .value) { snapshot in
    //         let pendingRequests = snapshot.value as? [String] ?? []
    //         print("DEBUG: Pending requests in Firebase: \(pendingRequests.count)")
    //
    //         for requestId in pendingRequests {
    //             print("DEBUG: Checking request: \(requestId)")
    //             dbRef.child("transferRequests").child(requestId).observeSingleEvent(of: .value) { requestSnapshot in
    //                 if let requestData = requestSnapshot.value as? [String: Any] {
    //                     print("DEBUG: Request \(requestId) data: \(requestData)")
    //                 } else {
    //                     print("DEBUG: Request \(requestId) not found!")
    //                 }
    //             }
    //         }
    //     }
    //
    //     // Check all transfer requests
    //     dbRef.child("transferRequests").observeSingleEvent(of: .value) { snapshot in
    //         if let allRequests = snapshot.value as? [String: [String: Any]] {
    //             print("DEBUG: Total transfer requests in system: \(allRequests.count)")
    //
    //             for (requestId, requestData) in allRequests {
    //                 if let fromUserId = requestData["fromUserId"] as? String,
    //                    let toUserId = requestData["toUserId"] as? String,
    //                    let status = requestData["status"] as? String,
    //                    fromUserId == currentUser.id.uuidString || toUserId == currentUser.id.uuidString {
    //                     print("DEBUG: Request involving current user: \(requestId)")
    //                     print("DEBUG: From: \(fromUserId), To: \(toUserId), Status: \(status)")
    //                 }
    //             }
    //         }
    //     }
    // }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
