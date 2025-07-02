import SwiftUI
import FirebaseDatabase

struct InvitationCodeView: View {
    @ObservedObject var appData: AppData
    @State private var invitationCode: String = ""
    @State private var name: String = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    @FocusState private var isInputActive: Bool
    
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
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Join with Invitation")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Enter your invitation details to join the room")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Invitation Details Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Invitation Details")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                TextField("Invitation Code", text: $invitationCode)
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
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
                                
                                TextField("Your Name", text: $name)
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
                        
                        // Join Button Section
                        VStack(spacing: 16) {
                            Button(action: validateInvitation) {
                                HStack {
                                    if isValidating {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.plus")
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
                                        gradient: Gradient(colors: (invitationCode.isEmpty || name.isEmpty || isValidating) ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: (invitationCode.isEmpty || name.isEmpty || isValidating) ? .clear : .blue.opacity(0.3), radius: (invitationCode.isEmpty || name.isEmpty || isValidating) ? 0 : 4, x: 0, y: 2)
                            }
                            .disabled(invitationCode.isEmpty || name.isEmpty || isValidating)
                        }
                        
                        // Info Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Need an invitation?")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    Text("Ask a room administrator for a 6-character invitation code")
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
            .onTapGesture {
                // Dismiss keyboard when tapping anywhere
                isInputActive = false
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
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
            }
        }
    }
    
    func validateInvitation() {
        let dbRef = Database.database().reference()
        isValidating = true
        errorMessage = nil
        
        print("Starting invitation validation for code: \(invitationCode)")
        
        dbRef.child("invitations").child(invitationCode).observeSingleEvent(of: .value) { snapshot, _ in
            if let invitation = snapshot.value as? [String: Any],
               let status = invitation["status"] as? String,
               (status == "invited" || status == "sent" || status == "created"),
               let roomId = invitation["roomId"] as? String {
                
                print("Valid invitation found. Status: \(status), RoomId: \(roomId)")
                
                // Verify room exists
                dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { roomSnapshot, _ in
                    guard roomSnapshot.exists() else {
                        print("Room \(roomId) does not exist")
                        self.errorMessage = "The room associated with this invitation no longer exists."
                        self.isValidating = false
                        return
                    }
                    
                    // Create a new user
                    let userId = UUID()
                    let isAdminInvite = invitation["isAdmin"] as? Bool ?? false
                    
                    let newUser = User(
                        id: userId,
                        name: self.name,
                        authId: nil,
                        ownedRooms: nil,
                        subscriptionPlan: nil,
                        roomLimit: 0,
                        isSuperAdmin: false,
                        pendingTransferRequests: nil,
                        roomAccess: [roomId: RoomAccess(
                            isActive: true,
                            joinedAt: Date(),
                            isAdmin: isAdminInvite
                        )],
                        roomSettings: nil
                    )
                    
                    print("Created new user: \(userId.uuidString), name: \(self.name), isAdmin: \(isAdminInvite)")
                    
                    // Save all operations to complete after Firebase updates
                    let completionOperations = {
                        print("Firebase operations completed, updating app state")
                        
                        // Set the current user
                        self.appData.currentUser = newUser
                        UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
                        
                        // Explicitly clear roomCode to prevent accidental room creation
                        self.appData.roomCode = nil
                        UserDefaults.standard.removeObject(forKey: "roomCode")
                        
                        // Set the currentRoomId
                        UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                        self.appData.currentRoomId = roomId
                        
                        print("App state updated: currentUser=\(userId.uuidString), currentRoomId=\(roomId)")
                        
                        // Dismiss and proceed to app
                        DispatchQueue.main.async {
                            self.dismiss()
                        }
                    }
                    
                    // Prepare multi-path update to ensure atomicity
                    var updates: [String: Any] = [
                        // Add user to global users node
                        "users/\(userId.uuidString)": newUser.toDictionary(),
                        // Grant room access with admin status
                        "users/\(userId.uuidString)/roomAccess/\(roomId)": [
                            "isActive": true,
                            "joinedAt": ISO8601DateFormatter().string(from: Date()),
                            "isAdmin": isAdminInvite
                        ],
                        // Mark invitation as accepted
                        "invitations/\(self.invitationCode)/status": "accepted",
                        "invitations/\(self.invitationCode)/acceptedBy": userId.uuidString,
                        // Add user to room's users node WITH admin status
                        "rooms/\(roomId)/users/\(userId.uuidString)": [
                            "id": userId.uuidString,
                            "name": self.name,
                            "isAdmin": isAdminInvite,
                            "joinedAt": ISO8601DateFormatter().string(from: Date())
                        ]
                    ]
                    
                    // Perform atomic update
                    dbRef.updateChildValues(updates) { error, _ in
                        if let error = error {
                            print("Error processing invitation: \(error.localizedDescription)")
                            self.errorMessage = "Error joining the room. Please try again."
                            self.isValidating = false
                            return
                        }
                        
                        print("Successfully joined room and updated all nodes with admin status: \(isAdminInvite)")
                        completionOperations()
                    }
                }
            } else {
                print("Invalid invitation. Snapshot exists: \(snapshot.exists()), Key: \(snapshot.key)")
                if let value = snapshot.value {
                    print("Value type: \(type(of: value))")
                }
                
                self.errorMessage = "Invalid or expired invitation code."
                self.isValidating = false
            }
        } withCancel: { error in
            print("Error validating invitation: \(error.localizedDescription)")
            self.errorMessage = "Error connecting to the server. Please try again."
            self.isValidating = false
        }
    }
}
