import SwiftUI
import FirebaseDatabase
import MessageUI

struct UserManagementView: View {
    @ObservedObject var appData: AppData
    @State private var users: [User] = []
    @State private var pendingInvitations: [String: [String: Any]] = [:]
    @State private var isShowingInviteSheet = false
    @State private var isLoading = true
    @State private var isShowingMessageComposer = false
    @State private var messageRecipient = ""
    @State private var messageBody = ""
    @State private var editedName: String = ""
    @State private var showingEditNameSheet = false
    @State private var selectedUser: User? = nil
    @Environment(\.presentationMode) var presentationMode
    @FocusState private var isInputActive: Bool
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading users...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern Header
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Manage Users")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("View and manage room members and invitations")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Current Users Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Current Users")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 12) {
                                ForEach(users.filter { user in
                                    // Hide super admin users unless current user is also super admin
                                    if user.isSuperAdmin && appData.currentUser?.isSuperAdmin != true {
                                        return false
                                    }
                                    // Hide users who joined with super admin access
                                    if let roomId = appData.currentRoomId,
                                       let roomAccess = user.roomAccess?[roomId],
                                       let roomAccessDict = try? JSONSerialization.data(withJSONObject: roomAccess.toDictionary()),
                                       let accessData = try? JSONSerialization.jsonObject(with: roomAccessDict) as? [String: Any],
                                       accessData["isSuperAdminAccess"] as? Bool == true,
                                       appData.currentUser?.isSuperAdmin != true {
                                        return false
                                    }
                                    return true
                                }) { user in
                                    HStack {
                                        // User Avatar
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Text(String(user.name.prefix(1)).uppercased())
                                                    .font(.headline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.blue)
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(user.name)
                                                .font(.headline)
                                                .fontWeight(.medium)
                                            
                                            HStack(spacing: 6) {
                                                let isUserAdmin = getUserAdminStatus(user)
                                                let isSuperAdmin = user.isSuperAdmin
                                                
                                                if isSuperAdmin {
                                                    Image(systemName: "crown.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.purple)
                                                    
                                                    Text("Super Admin")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.purple)
                                                } else {
                                                    Image(systemName: isUserAdmin ? "crown.fill" : "person.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(isUserAdmin ? .orange : .blue)
                                                    
                                                    Text(isUserAdmin ? "Admin" : "Regular User")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(isUserAdmin ? .orange : .blue)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule()
                                                    .fill(user.isSuperAdmin ? Color.purple.opacity(0.15) : (getUserAdminStatus(user) ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15)))
                                            )
                                        }
                                        
                                        Spacer()
                                        
                                        Menu {
                                            // Only show "Remove Admin" if not the last admin
                                            if getUserAdminStatus(user) && !isLastAdmin(user) {
                                                Button(action: {
                                                    toggleAdminStatus(user)
                                                }) {
                                                    Label("Remove Admin Permissions", systemImage: "person.fill.badge.minus")
                                                }
                                            } else if !getUserAdminStatus(user) {
                                                Button(action: {
                                                    toggleAdminStatus(user)
                                                }) {
                                                    Label("Make Admin", systemImage: "person.fill.badge.plus")
                                                }
                                            }
                                            
                                            // Only show edit name and sign out for current user
                                            if user.id == appData.currentUser?.id {
                                                Button(action: {
                                                    editedName = user.name
                                                    selectedUser = user
                                                    showingEditNameSheet = true
                                                }) {
                                                    Label("Edit Name", systemImage: "pencil")
                                                }
                                                
                                                // Only show sign out if not the last admin
                                                if !isLastAdmin(user) {
                                                    Button(action: {
                                                        signOut()
                                                    }) {
                                                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                                    }
                                                }
                                            }
                                            
                                            // Only show remove user if not the last admin
                                            if !(user.id == appData.currentUser?.id && isLastAdmin(user)) {
                                                Button(action: {
                                                    removeUser(user)
                                                }) {
                                                    Label("Remove User", systemImage: "trash")
                                                        .foregroundColor(.red)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                                .frame(width: 32, height: 32)
                                                .background(Color(.quaternarySystemFill))
                                                .clipShape(Circle())
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.tertiarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color(.separator), lineWidth: 0.5)
                                            )
                                    )
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            )
                        }
                        
                        // Pending Invitations Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Pending Invitations")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 12) {
                                if pendingInvitations.isEmpty {
                                    HStack {
                                        Image(systemName: "envelope")
                                            .font(.title2)
                                            .foregroundColor(.secondary)
                                        
                                        Text("No pending invitations")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 20)
                                } else {
                                    ForEach(Array(pendingInvitations.keys), id: \.self) { code in
                                        if let invitation = pendingInvitations[code] {
                                            HStack {
                                                // Invitation Icon
                                                Circle()
                                                    .fill(Color.orange.opacity(0.2))
                                                    .frame(width: 40, height: 40)
                                                    .overlay(
                                                        Image(systemName: "envelope.fill")
                                                            .font(.headline)
                                                            .foregroundColor(.orange)
                                                    )
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Code: \(code)")
                                                        .font(.headline)
                                                        .fontWeight(.medium)
                                                    
                                                    if let phone = invitation["phoneNumber"] as? String {
                                                        Text(phone)
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    HStack(spacing: 8) {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: invitation["isAdmin"] as? Bool == true ? "crown.fill" : "person.fill")
                                                                .font(.caption2)
                                                            Text(invitation["isAdmin"] as? Bool == true ? "Admin" : "Regular")
                                                                .font(.caption)
                                                        }
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            Capsule()
                                                                .fill(Color.blue.opacity(0.15))
                                                        )
                                                        .foregroundColor(.blue)
                                                        
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "clock")
                                                                .font(.caption2)
                                                            Text(invitation["status"] as? String ?? "Unknown")
                                                                .font(.caption)
                                                        }
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            Capsule()
                                                                .fill(Color.gray.opacity(0.15))
                                                        )
                                                        .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                Spacer()
                                                
                                                HStack(spacing: 8) {
                                                    Button(action: {
                                                        resendInvitation(code, invitation: invitation)
                                                    }) {
                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                            .font(.callout)
                                                            .foregroundColor(.blue)
                                                            .frame(width: 32, height: 32)
                                                            .background(Color.blue.opacity(0.1))
                                                            .clipShape(Circle())
                                                    }
                                                    
                                                    Button(action: {
                                                        deleteInvitation(code)
                                                    }) {
                                                        Image(systemName: "trash")
                                                            .font(.callout)
                                                            .foregroundColor(.red)
                                                            .frame(width: 32, height: 32)
                                                            .background(Color.red.opacity(0.1))
                                                            .clipShape(Circle())
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color(.tertiarySystemBackground))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color(.separator), lineWidth: 0.5)
                                                    )
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            )
                        }
                        
                        // Invite Button Section
                        VStack(spacing: 16) {
                            Button(action: {
                                isShowingInviteSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                        .font(.headline)
                                    Text("Invite New User")
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
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
        .sheet(isPresented: $isShowingInviteSheet) {
            NavigationView {
                InviteUserView(appData: appData, onComplete: {
                    // Only call loadData, don't dismiss the sheet yet
                    loadData()
                })
            }
        }
        .sheet(isPresented: $isShowingMessageComposer) {
            MessageComposeView(
                recipients: [messageRecipient],
                body: messageBody,
                isShowing: $isShowingMessageComposer,
                completion: { _ in }
            )
        }
        .sheet(isPresented: $showingEditNameSheet) {
            NavigationView {
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
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.blue, .purple]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Text("Edit Your Name")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                
                                Text("Update your display name")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 20)
                            
                            // Name Input Section
                            VStack(spacing: 20) {
                                HStack {
                                    Text("Your Name")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                VStack(spacing: 16) {
                                    TextField("Your Name", text: $editedName)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .focused($isInputActive)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.tertiarySystemBackground))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color(.separator), lineWidth: 1)
                                                )
                                        )
                                        .font(.body)
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.secondarySystemBackground))
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                )
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .onTapGesture {
                    // Dismiss keyboard when tapping anywhere
                    isInputActive = false
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingEditNameSheet = false }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Text("Back")
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            if let user = selectedUser, !editedName.isEmpty {
                                let updatedUser = User(
                                    id: user.id,
                                    name: editedName, // Use the edited name
                                    authId: user.authId,
                                    ownedRooms: user.ownedRooms,
                                    subscriptionPlan: user.subscriptionPlan,
                                    roomLimit: user.roomLimit,
                                    isSuperAdmin: user.isSuperAdmin,
                                    pendingTransferRequests: user.pendingTransferRequests,
                                    roomAccess: user.roomAccess,
                                    roomSettings: user.roomSettings
                                )
                                
                                // Update in AppData and Firebase
                                appData.addUser(updatedUser)
                                if appData.currentUser?.id == user.id {
                                    appData.currentUser = updatedUser
                                }
                                loadData() // Refresh the user list
                                
                                print("Updated user name to: \(editedName)")
                            }
                            showingEditNameSheet = false
                        }
                        .disabled(editedName.isEmpty)
                    }
                }
            }
        }
    }
    
    // Helper function to get user admin status for current room
    private func getUserAdminStatus(_ user: User) -> Bool {
        guard let currentRoomId = appData.currentRoomId else { return false }
        return user.roomAccess?[currentRoomId]?.isAdmin ?? false
    }
    
    // Check if this user is the last admin in the room
    private func isLastAdmin(_ user: User) -> Bool {
        guard let currentRoomId = appData.currentRoomId else { return false }
        let adminCount = users.filter { user in
            user.roomAccess?[currentRoomId]?.isAdmin == true
        }.count
        return getUserAdminStatus(user) && adminCount <= 1
    }
    
    // Sign out function
    func signOut() {
        // Clear user data
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentRoomId")
        appData.currentUser = nil
        appData.currentRoomId = nil
        
        // Notify ContentView to show login screen
        NotificationCenter.default.post(name: Notification.Name("UserDidSignOut"), object: nil)
        
        // Dismiss current view
        presentationMode.wrappedValue.dismiss()
    }
    
    func loadData() {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else {
            print("No currentRoomId found")
            isLoading = false
            return
        }
        
        isLoading = true
        users = []
        pendingInvitations = [:]
        
        print("Loading users for room: \(currentRoomId)")
        
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        // Load all users who have access to this room from the main users collection
        dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
            var roomUsers: [User] = []
            
            if let usersData = snapshot.value as? [String: [String: Any]] {
                for (userId, userData) in usersData {
                    // Check if this user has access to the current room
                    if let roomAccess = userData["roomAccess"] as? [String: Any],
                       let specificRoomAccess = roomAccess[currentRoomId] {
                        
                        // Handle both new dictionary format and old boolean format
                        let hasAccess: Bool
                        var isSuperAdminAccess = false
                        
                        if let accessDict = specificRoomAccess as? [String: Any] {
                            hasAccess = accessDict["isActive"] as? Bool ?? true
                            isSuperAdminAccess = accessDict["isSuperAdminAccess"] as? Bool ?? false
                        } else if let accessBool = specificRoomAccess as? Bool {
                            hasAccess = accessBool
                        } else {
                            hasAccess = false
                        }
                        
                        // Skip super admin access users unless current user is also super admin
                        if isSuperAdminAccess && self.appData.currentUser?.isSuperAdmin != true {
                            continue
                        }
                        
                        if hasAccess {
                            // Create user with full data from main users collection
                            var userDict = userData
                            userDict["id"] = userId
                            
                            if let user = User(dictionary: userDict) {
                                // Additional check for super admin users
                                if user.isSuperAdmin && self.appData.currentUser?.isSuperAdmin != true {
                                    continue
                                }
                                
                                roomUsers.append(user)
                                print("Added user: \(user.name) (ID: \(userId)), isAdmin: \(user.roomAccess?[currentRoomId]?.isAdmin ?? false)")
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.users = roomUsers
                print("Loaded \(roomUsers.count) users for room \(currentRoomId)")
                
                // Now load pending invitations
                dbRef.child("invitations").observeSingleEvent(of: .value) { snapshot in
                    guard let invitationsData = snapshot.value as? [String: [String: Any]] else {
                        self.isLoading = false
                        print("No invitations found")
                        return
                    }
                    
                    for (code, invitationData) in invitationsData {
                        if let roomId = invitationData["roomId"] as? String,
                           roomId == currentRoomId,
                           let status = invitationData["status"] as? String,
                           status != "accepted" {
                            self.pendingInvitations[code] = invitationData
                            print("Added pending invitation: \(code)")
                        }
                    }
                    
                    self.isLoading = false
                    print("Completed loading data for UserManagementView")
                }
            }
        }
    }
    
    func toggleAdminStatus(_ user: User) {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else { return }
        
        let dbRef = Database.database().reference()
        let currentIsAdmin = user.roomAccess?[currentRoomId]?.isAdmin ?? false
        let updatedAdmin = !currentIsAdmin
        
        // Don't allow removing last admin
        if currentIsAdmin && isLastAdmin(user) {
            return
        }
        
        // Update the admin status in room access
        dbRef.child("users").child(user.id.uuidString).child("roomAccess").child(currentRoomId).child("isAdmin").setValue(updatedAdmin) { error, _ in
            if error == nil {
                if let index = users.firstIndex(where: { $0.id == user.id }) {
                    // Create a new User with the updated admin status
                    var updatedUser = user
                    if updatedUser.roomAccess == nil {
                        updatedUser.roomAccess = [:]
                    }
                    if let roomAccess = updatedUser.roomAccess?[currentRoomId] {
                        updatedUser.roomAccess![currentRoomId] = RoomAccess(
                            isActive: roomAccess.isActive,
                            joinedAt: roomAccess.joinedAt,
                            isAdmin: updatedAdmin
                        )
                    }
                    
                    users[index] = updatedUser
                    
                    // Update currentUser if needed
                    if appData.currentUser?.id == user.id {
                        appData.currentUser = updatedUser
                    }
                }
            }
        }
    }
    
    func removeUser(_ user: User) {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else { return }
        
        let currentIsAdmin = user.roomAccess?[currentRoomId]?.isAdmin ?? false
        
        // Don't allow removing the last admin
        if currentIsAdmin && isLastAdmin(user) {
            return
        }
        
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        // Remove room access for this user
        dbRef.child("users").child(user.id.uuidString).child("roomAccess").child(currentRoomId).removeValue { error, _ in
            if error == nil {
                if let index = users.firstIndex(where: { $0.id == user.id }) {
                    users.remove(at: index)
                }
            }
        }
    }
    
    func deleteInvitation(_ code: String) {
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        dbRef.child("invitations").child(code).removeValue { error, _ in
            if error == nil {
                pendingInvitations.removeValue(forKey: code)
            }
        }
    }
    
    func resendInvitation(_ code: String, invitation: [String: Any]) {
        if let phoneNumber = invitation["phoneNumber"] as? String {
            // Update invitation status
            let dbRef = Database.database().reference()
            dbRef.child("invitations").child(code).child("status").setValue("sent")
            
            // Update local state
            if var updatedInvitation = pendingInvitations[code] {
                updatedInvitation["status"] = "sent"
                pendingInvitations[code] = updatedInvitation
            }
            
            // Show message composer with pre-populated text
            let appStoreLink = "https://testflight.apple.com/join/W93z4G4W" // Replace with your actual link
            let messageText = "You've been invited to use the TIPs App! Download here: \(appStoreLink) and use invitation code: \(code)"
            
            messageRecipient = phoneNumber
            messageBody = messageText
            isShowingMessageComposer = true
        }
    }
}
