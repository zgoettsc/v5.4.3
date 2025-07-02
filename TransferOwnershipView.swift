//
//  TransferOwnershipView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/24/25.
//


import SwiftUI
import FirebaseDatabase
import TelemetryDeck

struct TransferOwnershipView: View {
    @ObservedObject var appData: AppData
    let roomId: String
    let roomName: String
    @Environment(\.dismiss) var dismiss
    @State private var roomUsers: [User] = []
    @State private var isLoading = true
    @State private var selectedUser: User?
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isTransferring = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading room members...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if roomUsers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No Invited Users")
                            .font(.headline)
                        Text("You need to invite other users to this room before you can transfer ownership.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section(header: Text("SELECT NEW OWNER")) {
                            ForEach(roomUsers, id: \.id) { user in
                                UserSelectionRow(
                                    user: user,
                                    isSelected: selectedUser?.id == user.id
                                ) {
                                    selectedUser = user
                                }
                            }
                        }
                        
                        if let selectedUser = selectedUser {
                            Section(footer: Text("The selected user will become the new owner of this room. You will become a regular member.")) {
                                Button("Transfer Ownership") {
                                    showingConfirmation = true
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .disabled(isTransferring)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transfer Ownership")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: EmptyView()
            )
        }
        .onAppear {
            loadRoomUsers()
        }
        .alert("Transfer Request Sent", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
        .alert("Confirm Transfer", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Send Request") {  // Changed from "Transfer" to "Send Request"
                if let user = selectedUser {
                    transferOwnership(to: user)
                }
            }
        } message: {
            if let user = selectedUser {
                let roomCount = user.ownedRooms?.count ?? 0
                let roomLimit = user.roomLimit
                
                if roomLimit == 0 || roomCount >= roomLimit {
                    Text("Send ownership transfer request to \(user.name)?\n\nThey will need to upgrade their subscription to accept the transfer.")
                } else {
                    Text("Send ownership transfer request to \(user.name)?\n\nThey can accept immediately with their current subscription.")
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }
    
    private func loadRoomUsers() {
        guard let currentUserId = appData.currentUser?.id.uuidString else {
            print("DEBUG: No current user ID")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        print("DEBUG: Loading room users for room: \(roomId), current user: \(currentUserId)")
        
        let dbRef = Database.database().reference()
        
        // Get all users in this room (excluding the current owner)
        dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { snapshot in
            guard let usersData = snapshot.value as? [String: Any] else {
                print("DEBUG: No users data found in room")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            print("DEBUG: Found \(usersData.count) users in room")
            
            // Filter out the current user and get valid user IDs
            let otherUserIds = usersData.keys.filter { userId in
                guard !userId.isEmpty,
                      !userId.contains("."),
                      !userId.contains("#"),
                      !userId.contains("$"),
                      !userId.contains("["),
                      !userId.contains("]"),
                      userId != currentUserId else {
                    return false
                }
                return true
            }
            
            print("DEBUG: Found \(otherUserIds.count) valid other users: \(otherUserIds)")
            
            if otherUserIds.isEmpty {
                DispatchQueue.main.async {
                    self.roomUsers = []
                    self.isLoading = false
                }
                return
            }
            
            let group = DispatchGroup()
            var loadedUsers: [User] = []
            
            // Load fresh user data from Firebase (not from appData.users which might be stale)
            for userId in otherUserIds {
                group.enter()
                print("DEBUG: Loading FRESH user data for: \(userId)")
                
                // Get user data directly from Firebase to ensure it's current
                dbRef.child("users").child(userId).observeSingleEvent(of: .value) { userSnapshot in
                    defer { group.leave() }
                    
                    if let userData = userSnapshot.value as? [String: Any] {
                        // Add the ID to the dictionary to ensure User creation works
                        var mutableUserData = userData
                        mutableUserData["id"] = userId
                        
                        if let user = User(dictionary: mutableUserData) {
                            print("DEBUG: Successfully loaded user: \(user.name)")
                            print("DEBUG: User FRESH subscription data - ownedRooms: \(user.ownedRooms?.count ?? 0), roomLimit: \(user.roomLimit), subscriptionPlan: \(user.subscriptionPlan ?? "none")")
                            
                            loadedUsers.append(user)
                        } else {
                            print("DEBUG: Failed to create User object from data: \(userData)")
                        }
                    } else {
                        print("DEBUG: No data found for user: \(userId)")
                    }
                }
            }
            
            group.notify(queue: .main) {
                print("DEBUG: Finished loading \(loadedUsers.count) users with fresh data")
                
                // Filter out super admin users unless current user is also super admin
                let filteredUsers = loadedUsers.filter { user in
                    // Hide super admin users
                    if user.isSuperAdmin && self.appData.currentUser?.isSuperAdmin != true {
                        print("DEBUG: Filtering out super admin user: \(user.name)")
                        return false
                    }
                    
                    // Hide users who joined with super admin access
                    if let roomAccess = user.roomAccess?[self.roomId],
                       let accessDict = try? JSONSerialization.data(withJSONObject: roomAccess.toDictionary()),
                       let accessData = try? JSONSerialization.jsonObject(with: accessDict) as? [String: Any],
                       accessData["isSuperAdminAccess"] as? Bool == true,
                       self.appData.currentUser?.isSuperAdmin != true {
                        print("DEBUG: Filtering out super admin access user: \(user.name)")
                        return false
                    }
                    
                    return true
                }
                
                // Debug: Print all users and their ACTUAL capacities from fresh Firebase data
                for user in filteredUsers {
                    let roomCount = user.ownedRooms?.count ?? 0
                    let roomLimit = user.roomLimit
                    let canAccept = roomLimit > 0 && roomCount < roomLimit
                    print("DEBUG: User \(user.name) - FRESH DATA - rooms: \(roomCount)/\(roomLimit), canAccept: \(canAccept), plan: \(user.subscriptionPlan ?? "none")")
                }
                
                self.roomUsers = filteredUsers.sorted { $0.name < $1.name }
                self.isLoading = false
            }
        }
    }
    
    private func transferOwnership(to user: User) {
        isTransferring = true
        
        // Use the new owner-initiated transfer method
        appData.sendOwnerTransferRequest(
            roomId: roomId,
            roomName: roomName,
            toUserId: user.id
        ) { success, error in
            DispatchQueue.main.async {
                self.isTransferring = false
                
                if success {
                    let roomCount = user.ownedRooms?.count ?? 0
                    let roomLimit = user.roomLimit
                    let needsUpgrade = roomLimit == 0 || roomCount >= roomLimit
                    
                    self.successMessage = needsUpgrade ?
                        "The ownership transfer request has been sent to \(user.name). They will need to upgrade their subscription before they can accept." :
                        "The ownership transfer request has been sent to \(user.name). They will receive a notification to accept or decline."
                    
                    self.showingSuccessAlert = true
                } else {
                    self.errorMessage = error ?? "Failed to send transfer request"
                    self.showError = true
                }
            }
        }
    }
}

struct UserSelectionRow: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    
    private var subscriptionInfo: String {
        let roomCount = user.ownedRooms?.count ?? 0
        let roomLimit = user.roomLimit
        
        if roomLimit == 0 {
            return "No subscription"
        } else if roomCount >= roomLimit {
            return "Room limit reached (\(roomCount)/\(roomLimit))"
        } else {
            return "\(roomCount)/\(roomLimit) rooms used"
        }
    }
    
    private var subscriptionWarning: String? {
        let roomCount = user.ownedRooms?.count ?? 0
        let roomLimit = user.roomLimit
        
        if roomLimit == 0 {
            return "Will need to upgrade subscription to accept"
        } else if roomCount >= roomLimit {
            return "Will need to upgrade subscription to accept"
        } else {
            return nil
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.headline)
                
                Text(subscriptionInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let warning = subscriptionWarning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()  // Remove the canAcceptTransfer condition
        }
    }
}
