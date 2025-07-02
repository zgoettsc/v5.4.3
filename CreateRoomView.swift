import SwiftUI
import FirebaseDatabase
import FirebaseAuth
import TelemetryDeck

struct CreateRoomView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var participantName: String = ""
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var isCreatingRoom = false
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
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern Header
                        VStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Create New Room")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Set up a new room for your treatment program")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Participant Details Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Participant Details")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 20) {
                                // Name Input
                                VStack(spacing: 16) {
                                    TextField("Participant Name", text: $participantName)
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
                                
                                // Profile Image Section
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("Profile Photo")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("Optional")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    VStack(spacing: 16) {
                                        // Profile Image Display
                                        if let profileImage = profileImage {
                                            Image(uiImage: profileImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            LinearGradient(
                                                                gradient: Gradient(colors: [.blue, .purple]),
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 3
                                                        )
                                                )
                                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                        } else {
                                            Circle()
                                                .fill(Color(.quaternarySystemFill))
                                                .frame(width: 100, height: 100)
                                                .overlay(
                                                    Image(systemName: "person.crop.circle.fill")
                                                        .font(.system(size: 60))
                                                        .foregroundColor(.secondary)
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color(.separator), lineWidth: 1)
                                                )
                                        }
                                        
                                        // Choose Photo Button
                                        Button(action: {
                                            showingImagePicker = true
                                        }) {
                                            HStack {
                                                Image(systemName: "camera.fill")
                                                    .font(.callout)
                                                Text("Choose Photo")
                                                    .font(.callout)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(Color(.quaternarySystemFill))
                                            .foregroundColor(.blue)
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color(.separator), lineWidth: 1)
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
                        
                        // Create Room Button Section
                        VStack(spacing: 16) {
                            Button(action: {
                                createRoom()
                            }) {
                                HStack {
                                    if isCreatingRoom {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.headline)
                                    }
                                    
                                    Text(isCreatingRoom ? "Creating Room..." : "Create Room")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: (participantName.isEmpty || isCreatingRoom) ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: (participantName.isEmpty || isCreatingRoom) ? .clear : .blue.opacity(0.3), radius: (participantName.isEmpty || isCreatingRoom) ? 0 : 4, x: 0, y: 2)
                            }
                            .disabled(participantName.isEmpty || isCreatingRoom)
                        }
                        
                        // Info Section
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Room Creation")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    Text("You'll be the room administrator and can invite others to join")
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
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss keyboard when tapping anywhere
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $profileImage)
            }
        }
    }

    func createRoom() {
        guard !participantName.isEmpty, let user = appData.currentUser else {
            errorMessage = "Participant name or user missing"
            return
        }
        
        guard let userId = appData.currentUser?.id.uuidString else {
            errorMessage = "User ID missing"
            return
        }
        
        // Check room limit based on subscription plan
        let roomLimit = user.roomLimit
        let currentRoomCount = user.ownedRooms?.count ?? 0
        
        if roomLimit <= 0 {
            errorMessage = "You need an active subscription to create a room."
            return
        }
        
        if currentRoomCount >= roomLimit {
            errorMessage = "You've reached your room limit (\(roomLimit)). Please upgrade your subscription."
            return
        }
        
        isCreatingRoom = true
        TelemetryDeck.signal("room_created")
        
        // Create a new room ID
        let dbRef = Database.database().reference()
        let newRoomRef = dbRef.child("rooms").childByAutoId()
        guard let roomId = newRoomRef.key else {
            errorMessage = "Failed to generate room ID"
            isCreatingRoom = false
            return
        }
        
        // Create the room data
        let roomData: [String: Any] = [
            "users": [
                userId: [
                    "id": userId,
                    "name": user.name,
                    "isAdmin": true,
                    "joinedAt": ISO8601DateFormatter().string(from: Date())
                ]
            ],
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Save the room
        newRoomRef.setValue(roomData) { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create room: \(error.localizedDescription)"
                    self.isCreatingRoom = false
                }
                return
            }
            
            // Update user's room access with new structure
            let userRoomAccessRef = dbRef.child("users").child(userId).child("roomAccess").child(roomId)
            userRoomAccessRef.setValue([
                "joinedAt": ISO8601DateFormatter().string(from: Date()),
                "isActive": true,
                "isAdmin": true  // Creator is admin
            ])

            // Set initial room settings with new structure
            let userRoomSettingsRef = dbRef.child("users").child(userId).child("roomSettings").child(roomId)
            userRoomSettingsRef.setValue([
                "treatmentFoodTimerEnabled": true,  // Enable treatment timer by default
                "remindersEnabled": [:],  // No reminders enabled by default
                "reminderTimes": [:]
            ])
            
            // Update user's owned rooms
            var ownedRooms = user.ownedRooms ?? []
            ownedRooms.append(roomId)
            dbRef.child("users").child(userId).child("ownedRooms").setValue(ownedRooms)
            
            // Create the initial cycle
            let cycleId = UUID()
            let cycle = Cycle(
                id: cycleId,
                number: 1,
                patientName: self.participantName,
                startDate: Date(),
                foodChallengeDate: Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())!
            )
            
            // Save the cycle
            dbRef.child("rooms").child(roomId).child("cycles").child(cycleId.uuidString).setValue(cycle.toDictionary())
            
            // Update local state
            DispatchQueue.main.async {
                // Update user with new owned room
                if var updatedUser = self.appData.currentUser {
                    updatedUser.ownedRooms = ownedRooms
                    self.appData.currentUser = updatedUser
                }
                
                // Save participant info for cycle creation
                UserDefaults.standard.set(self.participantName, forKey: "pendingParticipantName")
                if let profileImage = self.profileImage, let imageData = profileImage.jpegData(compressionQuality: 0.7) {
                    UserDefaults.standard.set(imageData, forKey: "pendingProfileImage")
                }
                
                // Upload profile image
                if let profileImage = self.profileImage {
                    self.appData.saveProfileImage(profileImage, forCycleId: cycleId)
                    self.appData.uploadProfileImage(profileImage, forCycleId: cycleId) { _ in }
                }
                
                // Set current room and cycle
                self.appData.currentRoomId = roomId
                UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                UserDefaults.standard.set(true, forKey: "showFirstCyclePopup")
                UserDefaults.standard.set(cycleId.uuidString, forKey: "newCycleId")
                
                // Update app data
                self.appData.cycles = [cycle]
                
                // Reset state and dismiss
                self.isCreatingRoom = false

                // Notify of room creation
                NotificationCenter.default.post(
                    name: Notification.Name("RoomCreated"),
                    object: nil,
                    userInfo: ["roomId": roomId, "cycle": cycle]
                )

                // Navigate to home tab
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToHomeTab"),
                    object: nil
                )

                self.dismiss()
            }
        }
    }
}
