import SwiftUI
import FirebaseDatabase
import FirebaseAuth
import TelemetryDeck

struct JoinRoomView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var invitationCode: String = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    
    var body: some View {
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
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Join a Room")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Enter the invitation code to join an existing room")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Invitation Code Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Invitation Code")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                TextField("Enter invitation code", text: $invitationCode)
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                    .textFieldStyle(PlainTextFieldStyle())
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
                        
                        // Error Message Section
                        if let errorMessage = errorMessage {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.title3)
                                    
                                    Text(errorMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Action Button Section
                        VStack(spacing: 16) {
                            Button(action: validateInvitation) {
                                HStack {
                                    if isValidating {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.headline)
                                    }
                                    
                                    Text(isValidating ? "Joining Room..." : "Join Room")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: (invitationCode.isEmpty || isValidating) ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: (invitationCode.isEmpty || isValidating) ? .clear : .blue.opacity(0.3), radius: (invitationCode.isEmpty || isValidating) ? 0 : 4, x: 0, y: 2)
                            }
                            .disabled(invitationCode.isEmpty || isValidating)
                        }
                        
                        // Info Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("How to join a room")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    Text("Ask the room owner for an invitation code and enter it above")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(action: { dismiss() }) {
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
            )
        }
    }
    
    func validateInvitation() {
        let dbRef = Database.database().reference()
        isValidating = true
        TelemetryDeck.signal("room_joined")
        errorMessage = nil
        
        print("Starting invitation validation for code: \(invitationCode)")
        
        // First check regular invitations
        dbRef.child("invitations").child(invitationCode).observeSingleEvent(of: .value) { snapshot in
            if let invitation = snapshot.value as? [String: Any],
               let status = invitation["status"] as? String,
               (status == "invited" || status == "sent" || status == "created"),
               let roomId = invitation["roomId"] as? String,
               let phoneNumber = invitation["phoneNumber"] as? String,
               phoneNumber.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil || phoneNumber.isEmpty {
                
                print("Valid invitation found. Status: \(status), RoomId: \(roomId)")
                let isAdminInvite = invitation["isAdmin"] as? Bool ?? false
                print("Admin invite status: \(isAdminInvite)")
                
                self.processRoomJoin(roomId: roomId, isAdminInvite: isAdminInvite, isDemo: false)
                
            } else {
                // If not found in invitations, check demo room codes
                print("Not found in invitations, checking demo room codes...")
                dbRef.child("demoRoomCodes").observeSingleEvent(of: .value) { demoSnapshot in
                    var foundDemoCode = false
                    
                    if let allDemoCodes = demoSnapshot.value as? [String: [String: Any]] {
                        for (_, demoCodeData) in allDemoCodes {
                            if let code = demoCodeData["code"] as? String,
                               let isActive = demoCodeData["isActive"] as? Bool,
                               let roomId = demoCodeData["roomId"] as? String,
                               code.uppercased() == self.invitationCode.uppercased() && isActive {
                                
                                print("Valid demo room code found. RoomId: \(roomId)")
                                self.processRoomJoin(roomId: roomId, isAdminInvite: true, isDemo: true)
                                foundDemoCode = true
                                break
                            }
                        }
                    }
                    
                    if !foundDemoCode {
                        print("Code not found in demo room codes either")
                        self.errorMessage = "Invalid invitation code or phone number format."
                        self.isValidating = false
                    }
                }
            }
        }
    }
    private func processRoomJoin(roomId: String, isAdminInvite: Bool, isDemo: Bool) {
        let dbRef = Database.database().reference()
        
        dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { roomSnapshot in
            guard roomSnapshot.exists() else {
                print("Room \(roomId) does not exist")
                self.errorMessage = "The room associated with this invitation no longer exists."
                self.isValidating = false
                return
            }
            
            if let firebaseUser = Auth.auth().currentUser {
                // Get the Apple user ID from the user's provider data
                var appleUserId: String?
                for provider in firebaseUser.providerData {
                    if provider.providerID == "apple.com" {
                        appleUserId = provider.uid
                        break
                    }
                }
                
                guard let appleId = appleUserId else {
                    self.errorMessage = "Could not find Apple ID for current user"
                    self.isValidating = false
                    return
                }
                
                // Encode the Apple ID for Firebase lookup (same as AuthViewModel does)
                let encodedAppleId = appleId
                    .replacingOccurrences(of: ".", with: "_DOT_")
                    .replacingOccurrences(of: "#", with: "_HASH_")
                    .replacingOccurrences(of: "$", with: "_DOLLAR_")
                    .replacingOccurrences(of: "[", with: "_LBRACKET_")
                    .replacingOccurrences(of: "]", with: "_RBRACKET_")
                
                print("Looking up auth mapping for encoded Apple ID: \(encodedAppleId)")
                
                dbRef.child("auth_mapping").child(encodedAppleId).observeSingleEvent(of: .value) { authMapSnapshot in
                    if let userIdString = authMapSnapshot.value as? String {
                        // User exists - just update their room access
                        print("Found existing user: \(userIdString)")
                        
                        let joinedAt = ISO8601DateFormatter().string(from: Date())
                        
                        // Create room access data with admin status (demo codes give admin access)
                        let roomAccessData: [String: Any] = [
                            "isActive": true,
                            "joinedAt": joinedAt,
                            "isAdmin": isDemo ? true : isAdminInvite  // Demo codes always give admin access
                        ]
                        
                        // Mark all other rooms as inactive and add this room as active
                        dbRef.child("users").child(userIdString).child("roomAccess").observeSingleEvent(of: .value) { roomAccessSnapshot in
                            var updatedRoomAccess: [String: [String: Any]] = [:]
                            
                            if let existingAccess = roomAccessSnapshot.value as? [String: Any] {
                                for (existingRoomId, accessData) in existingAccess {
                                    var newAccess: [String: Any]
                                    
                                    if let accessDict = accessData as? [String: Any] {
                                        newAccess = accessDict
                                    } else if accessData as? Bool == true {
                                        newAccess = [
                                            "joinedAt": joinedAt,
                                            "isActive": false,
                                            "isAdmin": false
                                        ]
                                    } else {
                                        continue
                                    }
                                    
                                    newAccess["isActive"] = false
                                    updatedRoomAccess[existingRoomId] = newAccess
                                }
                            }
                            
                            // Add current room as active with admin status
                            updatedRoomAccess[roomId] = roomAccessData
                            
                            // Prepare multi-location update to ensure both user and room are updated atomically
                            var updates: [String: Any] = [:]
                            
                            // Update user's room access
                            updates["users/\(userIdString)/roomAccess"] = updatedRoomAccess
                            
                            // Get user's name first
                            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                                let userName = (userSnapshot.value as? [String: Any])?["name"] as? String ?? firebaseUser.displayName ?? "User"
                                
                                // Update room's users collection with admin status (demo codes give admin access)
                                updates["rooms/\(roomId)/users/\(userIdString)"] = [
                                    "id": userIdString,
                                    "name": userName,
                                    "isAdmin": isDemo ? true : isAdminInvite,  // Demo codes always give admin access
                                    "joinedAt": joinedAt
                                ]
                                
                                // Only mark invitation as accepted if it's not a demo code
                                if !isDemo {
                                    updates["invitations/\(self.invitationCode)/status"] = "accepted"
                                    updates["invitations/\(self.invitationCode)/acceptedBy"] = userIdString
                                } else {
                                    // Increment usage count for demo codes - find the correct roomId key
                                    dbRef.child("demoRoomCodes").observeSingleEvent(of: .value) { allCodesSnapshot in
                                        if let allCodes = allCodesSnapshot.value as? [String: [String: Any]] {
                                            for (roomIdKey, codeData) in allCodes {
                                                if let code = codeData["code"] as? String,
                                                   code.uppercased() == self.invitationCode.uppercased() {
                                                    let currentUsage = codeData["usageCount"] as? Int ?? 0
                                                    updates["demoRoomCodes/\(roomIdKey)/usageCount"] = currentUsage + 1
                                                    break
                                                }
                                            }
                                        }
                                                        
                                        // Perform atomic multi-location update
                                        print("Performing atomic update with admin status: \(isAdminInvite), demo: \(isDemo)")
                                        
                                        // Perform atomic multi-location update
                                        dbRef.updateChildValues(updates) { error, _ in
                                            if let error = error {
                                                print("Error performing atomic update: \(error.localizedDescription)")
                                                self.errorMessage = "Error joining room: \(error.localizedDescription)"
                                                self.isValidating = false
                                                return
                                            }
                                            
                                            print("Successfully joined room with admin status: \(isDemo ? true : isAdminInvite)")
                                            
                                            // Update app state to use existing user
                                            if let userData = userSnapshot.value as? [String: Any] {
                                                var userDict = userData
                                                userDict["id"] = userIdString
                                                
                                                if let user = User(dictionary: userDict) {
                                                    self.appData.currentUser = user
                                                }
                                            }
                                            
                                            self.appData.currentRoomId = roomId
                                            UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                                            
                                            DispatchQueue.main.async {
                                                NotificationCenter.default.post(name: Notification.Name("RoomJoined"), object: nil, userInfo: ["roomId": roomId])
                                                self.dismiss()
                                            }
                                        }
                                    }
                                }
                                
                                print("Performing atomic update with admin status: \(isAdminInvite), demo: \(isDemo)")
                                
                                // Perform atomic multi-location update
                                dbRef.updateChildValues(updates) { error, _ in
                                    if let error = error {
                                        print("Error performing atomic update: \(error.localizedDescription)")
                                        self.errorMessage = "Error joining room: \(error.localizedDescription)"
                                        self.isValidating = false
                                        return
                                    }
                                    
                                    print("Successfully joined room with admin status: \(isDemo ? true : isAdminInvite)")
                                    
                                    // Update app state to use existing user
                                    if let userData = userSnapshot.value as? [String: Any] {
                                        var userDict = userData
                                        userDict["id"] = userIdString
                                        
                                        if let user = User(dictionary: userDict) {
                                            self.appData.currentUser = user
                                        }
                                    }
                                    
                                    self.appData.currentRoomId = roomId
                                    UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                                    
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(name: Notification.Name("RoomJoined"), object: nil, userInfo: ["roomId": roomId])
                                        self.dismiss()
                                    }
                                }
                            }
                        }
                    } else {
                        self.errorMessage = "Could not find your account. Please try signing out and back in."
                        self.isValidating = false
                    }
                }
            } else {
                self.errorMessage = "You must be signed in to join a room"
                self.isValidating = false
            }
        }
    }
}
