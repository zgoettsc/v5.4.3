import SwiftUI
import FirebaseDatabase
import TelemetryDeck

struct RoomEntryView: View {
    let roomId: String
    let roomName: String
    let appData: AppData
    @State private var profileImage: UIImage? = nil
    @State private var cycleNumber: Int = 0
    @State private var week: Int = 0
    @State private var day: Int = 0
    @State private var showingLeaveAlert = false
    @State private var showingDeleteAlert = false
    @State private var leaveErrorMessage: String?
    @State private var showingActionSheet = false
    @State private var otherUsersCount = 0
    @State private var isRequestingOwnership = false
    @State private var showingOwnershipSuccessAlert = false
    @State private var ownershipErrorMessage: String?
    @State private var showingOwnershipErrorAlert = false
    
    private var isOwned: Bool {
        appData.currentUser?.ownedRooms?.contains(roomId) ?? false
    }
    
    private var shouldShowGracePeriodIndicator: Bool {
        if isOwned {
            // Owner sees their own grace period
            return appData.isInGracePeriod && appData.subscriptionGracePeriodEnd != nil
        } else {
            // Invited user sees room owner's grace period
            return appData.roomOwnerInGracePeriod && appData.roomOwnerGracePeriodEnd != nil
        }
    }
    
    private var gracePeriodDaysRemaining: Int {
        let gracePeriodEnd = isOwned ? appData.subscriptionGracePeriodEnd : appData.roomOwnerGracePeriodEnd
        guard let end = gracePeriodEnd else { return 0 }
        return Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(roomName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if cycleNumber > 0 {
                        Text("Cycle \(cycleNumber) • Week \(week) • Day \(day)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let errorMessage = leaveErrorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                // More options menu button
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.primary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, 0)
                .actionSheet(isPresented: $showingActionSheet) {
                    ActionSheet(
                        title: Text("Room Options"),
                        message: Text("Choose an action for this room"),
                        buttons: createActionSheetButtons()
                    )
                }
                .alert("Leave Room", isPresented: $showingLeaveAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Leave", role: .destructive) {
                        appData.leaveRoom(roomId: roomId) { success, error in
                            DispatchQueue.main.async {
                                if success {
                                    leaveErrorMessage = nil
                                    // Post notification to refresh ManageRoomsView
                                    NotificationCenter.default.post(name: Notification.Name("RoomLeft"), object: nil)
                                } else {
                                    leaveErrorMessage = error ?? "Failed to leave room"
                                }
                            }
                        }
                    }
                } message: {
                    Text("Are you sure you want to leave \(roomName)?")
                }
                .alert("Delete Room", isPresented: $showingDeleteAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        deleteRoom()
                    }
                } message: {
                    Text("Are you sure you want to permanently delete \(roomName) and all its data? This action cannot be undone.")
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
            
            // Grace period indicator
            if shouldShowGracePeriodIndicator {
                HStack {
                    Text("⚠️ \(gracePeriodDaysRemaining)d left")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                    
                    if !isOwned {
                        Button("Request Ownership") {
                            requestRoomOwnership()
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(isRequestingOwnership)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .onAppear {
            loadProfileImage()
            loadCycleDetails()
            checkOtherUsersInRoom()
        }
    }
    
    private func requestRoomOwnership() {
        isRequestingOwnership = true
        
        appData.requestRoomOwnership(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                self.isRequestingOwnership = false
                
                if success {
                    self.showingOwnershipSuccessAlert = true
                } else {
                    self.ownershipErrorMessage = error ?? "Failed to request ownership"
                    self.showingOwnershipErrorAlert = true
                }
            }
        }
    }
    
    private func deleteRoom() {
        TelemetryDeck.signal("room_deleted")
        appData.deleteRoom(roomId: roomId) { success, error in
            DispatchQueue.main.async {
                if success {
                    leaveErrorMessage = nil
                    // Post notification to refresh ManageRoomsView
                    NotificationCenter.default.post(name: Notification.Name("RoomDeleted"), object: nil)
                } else {
                    leaveErrorMessage = error ?? "Failed to delete room"
                }
            }
        }
    }
    
    private func loadProfileImage() {
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("cycles").observeSingleEvent(of: .value) { snapshot in
            if let cycles = snapshot.value as? [String: [String: Any]] {
                var latestCycleId: String? = nil
                var latestStartDate: Date? = nil
                
                for (cycleId, cycleData) in cycles {
                    if let startDateStr = cycleData["startDate"] as? String,
                       let startDate = ISO8601DateFormatter().date(from: startDateStr) {
                        if latestStartDate == nil || startDate > latestStartDate! {
                            latestStartDate = startDate
                            latestCycleId = cycleId
                        }
                    }
                }
                
                if let cycleId = latestCycleId, let uuid = UUID(uuidString: cycleId) {
                    self.profileImage = appData.loadProfileImage(forCycleId: uuid)
                }
            }
        }
    }
    
    private func loadCycleDetails() {
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("cycles").observeSingleEvent(of: .value) { snapshot in
            if let cycles = snapshot.value as? [String: [String: Any]] {
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
                
                if let cycleData = latestCycle,
                   let cycleNumber = cycleData["number"] as? Int,
                   let startDateStr = cycleData["startDate"] as? String,
                   let startDate = ISO8601DateFormatter().date(from: startDateStr) {
                    self.cycleNumber = cycleNumber
                    
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let cycleStartDay = calendar.startOfDay(for: startDate)
                    let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
                    
                    let days = max(1, daysSinceStart + 1)
                    self.week = max(1, (days - 1) / 7 + 1)
                    self.day = max(1, (days - 1) % 7 + 1)
                } else {
                    self.cycleNumber = 1
                    self.week = 1
                    self.day = 1
                }
            } else {
                self.cycleNumber = 1
                self.week = 1
                self.day = 1
            }
        }
    }
    
    private func createActionSheetButtons() -> [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = []
        
        // Check if current user owns this room
        if isOwned {
            // Owner options: Transfer or Delete only
            
            // Only show transfer if there are other users in the room
            if hasOtherUsersInRoom() {
                buttons.append(.default(Text("Transfer Ownership")) {
                    print("DEBUG: Transfer ownership tapped for room: \(roomId)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowTransferOwnership"),
                            object: nil,
                            userInfo: ["roomId": self.roomId, "roomName": self.roomName]
                        )
                    }
                })
            }
            
            buttons.append(.destructive(Text("Delete Room")) {
                showingDeleteAlert = true
            })
        } else {
            // Invited user options: Leave and optionally Request Ownership
            buttons.append(.destructive(Text("Leave Room")) {
                showingLeaveAlert = true
            })
            
            // Add request ownership option if room owner is in grace period
            if appData.roomOwnerInGracePeriod {
                buttons.append(.default(Text("Request Ownership")) {
                    requestRoomOwnership()
                })
            }
        }
        
        buttons.append(.cancel())
        return buttons
    }

    private func hasOtherUsersInRoom() -> Bool {
        return otherUsersCount > 0
    }
    
    private func checkOtherUsersInRoom() {
        guard let currentUserId = appData.currentUser?.id.uuidString else { return }
        
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { snapshot in
            if let usersData = snapshot.value as? [String: Any] {
                let otherUsers = usersData.keys.filter { $0 != currentUserId }
                DispatchQueue.main.async {
                    self.otherUsersCount = otherUsers.count
                }
            }
        }
    }
}
