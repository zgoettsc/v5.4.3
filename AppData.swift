import Foundation
import SwiftUI
import FirebaseDatabase
import FirebaseStorage
import FirebaseAuth
import FirebaseRemoteConfig
import ActivityKit

class AppData: ObservableObject {
    @Published var cycles: [Cycle] = []
    @Published var cycleItems: [UUID: [Item]] = [:]
    @Published var groupedItems: [UUID: [GroupedItem]] = [:]
    @Published var units: [Unit] = []
    @Published var consumptionLog: [UUID: [UUID: [LogEntry]]] = [:]
    @Published var lastResetDate: Date?
    @Published var users: [User] = []
    @Published var currentUser: User? {
        didSet { saveCurrentUserSettings() }
    }
    @Published var treatmentTimer: TreatmentTimer? {
        didSet {
            saveTimerState()
        }
    }
    private var lastSaveTime: Date?
    private var isCleaningUp = false
    @Published var categoryCollapsed: [String: Bool] = [:]
    @Published var groupCollapsed: [UUID: Bool] = [:] // Keyed by group ID
    @Published var subscriptionGracePeriodEnd: Date?
    @Published var isInGracePeriod: Bool = false
    @Published var roomOwnerGracePeriodEnd: Date?
    @Published var roomOwnerInGracePeriod: Bool = false
    @Published var hasPendingOwnershipRequests: Bool = false
    @Published var roomCode: String? = nil // Remove the didSet entirely
    @Published var syncError: String?
    @Published var isLoading: Bool = true
    @Published var sentTransferRequests: [TransferRequest] = []  // NEW: Track sent requests
    @Published var currentRoomId: String? {
        didSet {
            if let roomId = currentRoomId {
                //   // print("Setting currentRoomId to: \(roomId)")
                UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                
                // Clear roomCode to avoid confusion
                self.roomCode = nil
                UserDefaults.standard.removeObject(forKey: "roomCode")
                
                // Reset state but preserve timer
                resetStateForNewRoom()
                
                // Load room data and restore timer
                loadRoomData(roomId: roomId)
            } else {
                //  // print("Clearing currentRoomId")
                UserDefaults.standard.removeObject(forKey: "currentRoomId")
                // Do not clear timer state here
                //   // print("Preserving timer state during room switch")
                self.logToFile("Preserving timer state during room switch")
            }
        }
    }
    @Published var activeTimers: [String: TreatmentTimer] = [:] // Keyed by roomId
    @Published var reactions: [UUID: [Reaction]] = [:]  // Key is cycleId
    @Published var treatmentTimerOverride: TreatmentTimerOverride = TreatmentTimerOverride()
    @Published var missedDoses: [UUID: [MissedDose]] = [:] // CycleId -> MissedDoses
    private var isCheckingTimers = false
    
    private func debugStatusChange(requestId: String, newStatus: String, location: String) {
        print("🚨 STATUS CHANGE: Request \(requestId) status changed to \(newStatus) at location: \(location)")
        print("🚨 STACK TRACE: \(Thread.callStackSymbols.prefix(5))")
    }
    
    func addReaction(_ reaction: Reaction, toCycleId cycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == cycleId }) else {
            completion(false)
            return
        }
        
        let reactionRef = dbRef.child("cycles").child(cycleId.uuidString).child("reactions").child(reaction.id.uuidString)
        
        // First update local state immediately for better UI responsiveness
        DispatchQueue.main.async {
            if var cycleReactions = self.reactions[cycleId] {
                if let index = cycleReactions.firstIndex(where: { $0.id == reaction.id }) {
                    cycleReactions[index] = reaction
                } else {
                    cycleReactions.append(reaction)
                }
                self.reactions[cycleId] = cycleReactions
            } else {
                self.reactions[cycleId] = [reaction]
            }
            self.objectWillChange.send()
        }
        
        // Then update Firebase
        reactionRef.setValue(reaction.toDictionary()) { error, _ in
            if let error = error {
                // print("Error adding reaction \(reaction.id) to Firebase: \(error)")
                self.logToFile("Error adding reaction \(reaction.id) to Firebase: \(error)")
                
                // Revert local state if Firebase update fails
                DispatchQueue.main.async {
                    if var cycleReactions = self.reactions[cycleId] {
                        cycleReactions.removeAll { $0.id == reaction.id }
                        if !cycleReactions.isEmpty {
                            self.reactions[cycleId] = cycleReactions
                        } else {
                            self.reactions.removeValue(forKey: cycleId)
                        }
                        self.objectWillChange.send()
                    }
                }
                
                completion(false)
            } else {
                DispatchQueue.main.async {
                    // Firebase observer will handle the update
                    // print("Successfully added reaction \(reaction.id) to Firebase")
                    self.saveCachedData()
                    completion(true)
                }
            }
        }
    }
    
    func removeReaction(_ reactionId: UUID, fromCycleId cycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == cycleId }) else { return }
        
        // First update local state immediately for better UI responsiveness
        DispatchQueue.main.async {
            if var cycleReactions = self.reactions[cycleId] {
                cycleReactions.removeAll { $0.id == reactionId }
                self.reactions[cycleId] = cycleReactions
                self.objectWillChange.send()
            }
        }
        
        // Then update Firebase
        dbRef.child("cycles").child(cycleId.uuidString).child("reactions").child(reactionId.uuidString).removeValue { error, _ in
            if let error = error {
                // print("Error removing reaction \(reactionId) from Firebase: \(error)")
                self.logToFile("Error removing reaction \(reactionId) from Firebase: \(error)")
            } else {
                // print("Successfully removed reaction \(reactionId) from Firebase")
                self.saveCachedData()
            }
        }
    }
    
    func uploadProfileImage(_ image: UIImage, forCycleId cycleId: UUID, completion: @escaping (Bool) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(false)
            return
        }
        
        let storageRef = Storage.storage().reference()
        let imagePath = "profileImages/\(cycleId.uuidString).jpg"
        let imageRef = storageRef.child(imagePath)
        
        // Upload the image
        let uploadTask = imageRef.putData(imageData, metadata: nil) { metadata, error in
            if error != nil {
                // print("Error uploading image: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }
            
            // Get download URL
            imageRef.downloadURL { url, error in
                if let error = error {
                    // print("Error getting download URL: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let downloadURL = url?.absoluteString else {
                    completion(false)
                    return
                }
                
                // Save URL reference to database
                if let dbRef = self.dbRef {
                    dbRef.child("cycles").child(cycleId.uuidString).child("profileImageURL").setValue(downloadURL) { error, _ in
                        if let error = error {
                            // print("Error saving image URL: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            // Still save locally for offline access
                            self.saveProfileImage(image, forCycleId: cycleId)
                            completion(true)
                        }
                    }
                } else {
                    // Save locally if Firebase not available
                    self.saveProfileImage(image, forCycleId: cycleId)
                    completion(false)
                }
            }
        }
        
        uploadTask.resume()
    }
    
    func downloadProfileImage(forCycleId cycleId: UUID, completion: @escaping (UIImage?) -> Void) {
        // First try to get from local cache
        if let localImage = loadProfileImage(forCycleId: cycleId) {
            completion(localImage)
            return
        }
        
        // If not in cache, try Firebase
        if let dbRef = dbRef {
            dbRef.child("cycles").child(cycleId.uuidString).child("profileImageURL").observeSingleEvent(of: .value) { snapshot in
                guard let urlString = snapshot.value as? String,
                      let url = URL(string: urlString) else {
                    completion(nil)
                    return
                }
                
                // Download image from URL
                URLSession.shared.dataTask(with: url) { data, response, error in
                    guard let data = data, error == nil,
                          let image = UIImage(data: data) else {
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Save to local cache and return
                    self.saveProfileImage(image, forCycleId: cycleId)
                    DispatchQueue.main.async {
                        completion(image)
                    }
                }.resume()
            }
        } else {
            completion(nil)
        }
    }
    
    // Add this method to the AppData class
    func clearGroupedItems(forCycleId cycleId: UUID) {
        // Clear in memory
        groupedItems[cycleId] = []
        
        // Clear in Firebase
        if let dbRef = dbRef {
            dbRef.child("cycles").child(cycleId.uuidString).child("groupedItems").setValue([:])
            // print("Cleared grouped items for cycle \(cycleId) in Firebase")
        } else {
            // print("No database reference available, only cleared grouped items in memory")
        }
    }
    
    private var dataRefreshObservers: [UUID: () -> Void] = [:]
    
    func addDataRefreshObserver(id: UUID, handler: @escaping () -> Void) {
        dataRefreshObservers[id] = handler
    }
    
    func removeDataRefreshObserver(id: UUID) {
        dataRefreshObservers.removeValue(forKey: id)
    }
    
    func notifyDataRefreshObservers() {
        DispatchQueue.main.async {
            for handler in self.dataRefreshObservers.values {
                handler()
            }
        }
    }
    
    // Add to AppData class
    func createUserFromAppleAuth(appleId: String, name: String, isAdmin: Bool = true) -> User {
        let userId = UUID()
        let user = User(
            id: userId,
            name: name,
            authId: appleId, // Store Apple ID instead of Firebase UID
            ownedRooms: nil,
            subscriptionPlan: nil,
            roomLimit: 0
        )
        
        addUser(user)
        currentUser = user
        UserDefaults.standard.set(userId.uuidString, forKey: "currentUserId")
        return user
    }
    
    
    func linkUserToAppleAuth(user: User, appleId: String) {
        let dbRef = Database.database().reference()
        
        // print("AppData: Linking user \(user.id) to Apple ID \(appleId)")
        
        // Create a mapping between Apple ID and our app's UUID
        dbRef.child("auth_mapping").child(appleId).setValue(user.id.uuidString)
        
        // Also add Apple ID directly to user record
        dbRef.child("users").child(user.id.uuidString).updateChildValues([
            "authId": appleId
        ]) { error, _ in
            if let error = error {
                // print("Error adding Apple ID to user: \(error.localizedDescription)")
            } else {
                // print("Successfully added Apple ID to user \(user.id)")
            }
        }
    }
    
    
    func forceRefreshCurrentUser(completion: (() -> Void)? = nil) {
        guard let currentRoomId = currentRoomId else {
            completion?()
            return
        }
        
        guard let userId = currentUser?.id.uuidString else {
            // print("AppData: Cannot refresh user - no user ID")
            completion?()
            return
        }
        
        // print("AppData: Force refreshing user data for \(userId)")
        let dbRef = Database.database().reference()
        
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { [weak self] snapshot, _ in
            guard let self = self else {
                completion?()
                return
            }
            
            if let userData = snapshot.value as? [String: Any] {
                var userDict = userData
                userDict["id"] = userId
                
                // Make sure required fields exist to avoid creation errors
                if userDict["name"] == nil {
                    userDict["name"] = self.currentUser?.name ?? "User"
                }
                
                if let user = User(dictionary: userDict) {
                    // print("AppData: Refreshed user data with plan: \(user.subscriptionPlan ?? "none"), limit: \(user.roomLimit)")
                    
                    DispatchQueue.main.async {
                        // Only update if the name hasn't been changed locally in the last 10 seconds
                        let now = Date()
                        if let lastUpdate = self.lastUserNameUpdate,
                           now.timeIntervalSince(lastUpdate) < 10.0,
                           user.name != self.currentUser?.name {
                            // print("AppData: Skipping name update - user recently updated name locally")
                            // print("DEBUG: Last update: \(lastUpdate), now: \(now), time diff: \(now.timeIntervalSince(lastUpdate))")
                            // print("DEBUG: Firebase name: '\(user.name)', local name: '\(self.currentUser?.name ?? "nil")'")
                            
                            // Update everything except the name
                            var preservedUser = user
                            preservedUser = User(
                                id: user.id,
                                name: self.currentUser?.name ?? user.name, // Keep current name
                                authId: user.authId,
                                ownedRooms: user.ownedRooms,
                                subscriptionPlan: user.subscriptionPlan,
                                roomLimit: user.roomLimit,
                                isSuperAdmin: user.isSuperAdmin,
                                pendingTransferRequests: user.pendingTransferRequests,
                                roomAccess: user.roomAccess,
                                roomSettings: user.roomSettings
                            )
                            self.currentUser = preservedUser
                            // print("DEBUG: Preserved local name: '\(preservedUser.name)'")
                        } else {
                            // Update normally
                            // print("DEBUG: Updating normally - Firebase name: '\(user.name)', local name: '\(self.currentUser?.name ?? "nil")'")
                            if let lastUpdate = self.lastUserNameUpdate {
                                // print("DEBUG: Last update: \(lastUpdate), now: \(now), time diff: \(now.timeIntervalSince(lastUpdate))")
                            } else {
                                // print("DEBUG: No lastUserNameUpdate recorded")
                            }
                            self.currentUser = user
                        }
                        
                        self.objectWillChange.send()
                        
                        // Notify views with a single notification
                        NotificationCenter.default.post(
                            name: Notification.Name("UserDataRefreshed"),
                            object: nil,
                            userInfo: [
                                "plan": user.subscriptionPlan ?? "none",
                                "limit": user.roomLimit,
                                "ownedRooms": user.ownedRooms ?? []
                            ]
                        )
                        
                        completion?()
                    }
                } else {
                    // print("AppData: Failed to parse user data")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("SubscriptionUpdateFailed"),
                            object: nil,
                            userInfo: ["error": "Failed to process user data"]
                        )
                        completion?()
                    }
                }
            } else {
                // print("AppData: Failed to refresh user data")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("SubscriptionUpdateFailed"),
                        object: nil,
                        userInfo: ["error": "Failed to refresh user data"]
                    )
                    completion?()
                }
            }
        }
    }
    
    private var lastUserNameUpdate: Date?
    
    func getUserByAppleId(appleId: String, completion: @escaping (User?) -> Void) {
        let dbRef = Database.database().reference()
        
        // Look up the user UUID from auth mapping using Apple ID
        dbRef.child("auth_mapping").child(appleId).observeSingleEvent(of: .value) { snapshot in
            guard let userIdString = snapshot.value as? String,
                  let userId = UUID(uuidString: userIdString) else {
                completion(nil)
                return
            }
            
            // Get the user data
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                guard let userData = userSnapshot.value as? [String: Any],
                      let user = User(dictionary: userData) else {
                    completion(nil)
                    return
                }
                
                DispatchQueue.main.async {
                    self.currentUser = user
                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                    completion(user)
                }
            }
        }
    }
    
    // Function to start a new treatment timer
    func startTreatmentTimer(duration: TimeInterval? = nil, roomId: String? = nil) {
        let targetRoomId = roomId ?? currentRoomId
        guard let roomId = targetRoomId else {
            // print("No room ID provided, cannot start timer")
            self.logToFile("No room ID provided, cannot start timer")
            return
        }
        
        // Use effective duration if none provided
        let effectiveDuration = duration ?? getEffectiveTreatmentTimerDuration()
        
        stopTreatmentTimer(roomId: roomId)
        
        let unloggedItems = getUnloggedTreatmentItems()
        if unloggedItems.isEmpty {
            // print("No unlogged treatment items for room \(roomId), not starting timer")
            self.logToFile("No unlogged treatment items for room \(roomId), not starting timer")
            return
        }
        
        let participantName = cycles.first(where: { $0.id == currentCycleId() })?.patientName ?? "Unknown"
        let endTime = Date().addingTimeInterval(effectiveDuration)
        let timerId = "treatment_timer_\(UUID().uuidString)"
        
        let notificationIds = scheduleNotifications(timerId: timerId, endTime: endTime, duration: effectiveDuration, participantName: participantName, roomId: roomId)
        
        let newTimer = TreatmentTimer(
            id: timerId,
            isActive: true,
            endTime: endTime,
            associatedItemIds: unloggedItems.map { $0.id },
            notificationIds: notificationIds,
            roomName: participantName
        )
        
        activeTimers[roomId] = newTimer
        // Start Live Activity
        if #available(iOS 16.1, *) {
            startLiveActivity(roomId: roomId, roomName: participantName, endTime: endTime, duration: effectiveDuration)
        }
        if roomId == currentRoomId {
            treatmentTimer = newTimer
            treatmentTimerId = timerId
            saveTimerState()
        }
        
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("treatmentTimer").setValue(newTimer.toDictionary()) { error, _ in
            if let error = error {
                // print("Failed to save timer to Firebase for room \(roomId): \(error)")
                self.logToFile("Failed to save timer to Firebase for room \(roomId): \(error)")
            } else {
                // print("Saved timer to Firebase for room \(roomId)")
                self.logToFile("Saved timer to Firebase for room \(roomId)")
            }
        }
    }
    // Get unlogged treatment items
    private func getUnloggedTreatmentItems() -> [Item] {
        guard let cycleId = currentCycleId() else { return [] }
        
        let treatmentItems = (cycleItems[cycleId] ?? []).filter { $0.category == .treatment }
        
        // If there are no treatment items at all, return empty array
        if treatmentItems.isEmpty {
            return []
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        return treatmentItems.filter { item in
            let logs = consumptionLog[cycleId]?[item.id] ?? []
            return !logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
    }
    
    func leaveRoom(roomId: String, completion: @escaping (Bool, String?) -> Void) {
        // Get direct reference to the main database
        let mainDbRef = Database.database().reference()
        
        guard let userId = currentUser?.id.uuidString else {
            completion(false, "User ID not available")
            return
        }
        
        // First check if we still have access to the room
        mainDbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            if !snapshot.exists() {
                // Create an empty room access node if it doesn't exist
                mainDbRef.child("users").child(userId).child("roomAccess").setValue([:]) { error, _ in
                    if let error = error {
                        completion(false, "Error creating roomAccess: \(error.localizedDescription)")
                    } else {
                        // Try again after creating the node
                        self.leaveRoom(roomId: roomId, completion: completion)
                    }
                }
                return
            }
            
            let accessibleRooms = snapshot.children.compactMap { ($0 as? DataSnapshot)?.key }
            
            // Remove room access
            mainDbRef.child("users").child(userId).child("roomAccess").child(roomId).removeValue { error, _ in
                if let error = error {
                    completion(false, "Error leaving room: \(error.localizedDescription)")
                    return
                }
                
                // Remove user from room's users
                mainDbRef.child("rooms").child(roomId).child("users").child(userId).removeValue { error, _ in
                    if let error = error {
                        completion(false, "Error updating room users: \(error.localizedDescription)")
                        return
                    }
                    
                    // If leaving the active room, handle room switch
                    if roomId == self.currentRoomId {
                        if let nextRoomId = accessibleRooms.first(where: { $0 != roomId }) {
                            // Switch to another room
                            self.currentRoomId = nextRoomId
                            UserDefaults.standard.set(nextRoomId, forKey: "currentRoomId")
                        } else {
                            // No other rooms, clear currentRoomId
                            self.currentRoomId = nil
                            UserDefaults.standard.removeObject(forKey: "currentRoomId")
                        }
                    }
                    
                    // Post notification to refresh
                    NotificationCenter.default.post(name: Notification.Name("RoomLeft"), object: nil)
                    completion(true, nil)
                }
            }
        }
    }
    // Function to stop the treatment timer
    func stopTreatmentTimer(clearRoom: Bool = false, roomId: String? = nil) {
        print("AppData: Stopping treatment timer, clearRoom: \(clearRoom), roomId: \(roomId ?? "all")")
        self.logToFile("AppData: Stopping treatment timer, clearRoom: \(clearRoom), roomId: \(roomId ?? "all")")
        
        if let specificRoomId = roomId {
            // Stop timer for a specific room
            if let timer = activeTimers[specificRoomId], timer.isActive {
                // Cancel ALL notifications for this timer (all users)
                cancelAllNotificationsForTimer(timerId: timer.id, roomId: specificRoomId)
                
                if clearRoom {
                    // End Live Activity
                    if #available(iOS 16.1, *) {
                        endLiveActivity(roomId: specificRoomId)
                    }
                    let dbRef = Database.database().reference()
                    dbRef.child("rooms").child(specificRoomId).child("treatmentTimer").removeValue { error, _ in
                        if let error = error {
                            print("Failed to remove timer from Firebase for room \(specificRoomId): \(error)")
                            self.logToFile("Failed to remove timer from Firebase for room \(specificRoomId): \(error)")
                        } else {
                            print("Successfully removed timer from Firebase for room \(specificRoomId)")
                            self.logToFile("Successfully removed timer from Firebase for room \(specificRoomId)")
                        }
                    }
                    activeTimers.removeValue(forKey: specificRoomId)
                    if specificRoomId == currentRoomId {
                        treatmentTimer = nil
                        treatmentTimerId = nil
                        saveTimerState()
                    }
                }
            }
        } else {
            // Stop all timers
            for (roomId, timer) in activeTimers where timer.isActive {
                // Cancel ALL notifications for this timer (all users)
                cancelAllNotificationsForTimer(timerId: timer.id, roomId: roomId)
                
                if clearRoom {
                    let dbRef = Database.database().reference()
                    dbRef.child("rooms").child(roomId).child("treatmentTimer").removeValue { error, _ in
                        if let error = error {
                            print("Failed to remove timer from Firebase for room \(roomId): \(error)")
                            self.logToFile("Failed to remove timer from Firebase for room \(roomId): \(error)")
                        } else {
                            print("Successfully removed timer from Firebase for room \(roomId)")
                            self.logToFile("Successfully removed timer from Firebase for room \(roomId)")
                        }
                    }
                }
            }
            
            if clearRoom {
                // End Live Activities for all rooms
                if #available(iOS 16.1, *) {
                    for roomId in activeTimers.keys {
                        endLiveActivity(roomId: roomId)
                    }
                }
                activeTimers.removeAll()
                treatmentTimer = nil
                treatmentTimerId = nil
                saveTimerState()
            }
        }
    }
    
    private func cancelAllNotificationsForTimer(timerId: String, roomId: String) {
        print("Cancelling all notifications for timer \(timerId) in room \(roomId)")
        self.logToFile("Cancelling all notifications for timer \(timerId) in room \(roomId)")
        
        // Get all pending notifications and cancel ones that match this timer
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiersToCancel = requests.compactMap { request -> String? in
                // Check if this notification belongs to our timer
                let userInfo = request.content.userInfo
                if let notificationTimerId = userInfo["timerId"] as? String,
                   let notificationRoomId = userInfo["roomId"] as? String,
                   notificationTimerId == timerId && notificationRoomId == roomId {
                    return request.identifier
                }
                // Also check for old format notifications that start with the timer ID
                if request.identifier.hasPrefix(timerId) {
                    return request.identifier
                }
                return nil
            }
            
            if !identifiersToCancel.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
                print("Cancelled \(identifiersToCancel.count) notifications for timer \(timerId): \(identifiersToCancel)")
                self.logToFile("Cancelled \(identifiersToCancel.count) notifications for timer \(timerId): \(identifiersToCancel)")
            } else {
                print("No pending notifications found for timer \(timerId)")
                self.logToFile("No pending notifications found for timer \(timerId)")
            }
        }
    }
    
    // In AppData.swift, add this method to check for active timers on initialization
    func checkForActiveTimers() {
        guard let userId = currentUser?.id.uuidString else {
            logToFile("Cannot check for active timers: no user ID")
            return
        }
        
        // Prevent multiple simultaneous checks
        guard !isCheckingTimers else {
            logToFile("Timer check already in progress, skipping")
            return
        }
        isCheckingTimers = true
        
        let dbRef = Database.database().reference()
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            defer { self.isCheckingTimers = false }
            
            guard let roomAccess = snapshot.value as? [String: Any] else {
                print("No accessible rooms found for user \(userId)")
                return
            }
            
            self.setupTimerObserversForAllRooms(roomIds: Array(roomAccess.keys))
            
            let group = DispatchGroup()
            var newActiveTimers: [String: TreatmentTimer] = [:]
            
            for (roomId, _) in roomAccess {
                group.enter()
                dbRef.child("rooms").child(roomId).child("treatmentTimer").observeSingleEvent(of: .value) { timerSnapshot in
                    defer { group.leave() }
                    if let timerDict = timerSnapshot.value as? [String: Any],
                       let timerObj = TreatmentTimer.fromDictionary(timerDict),
                       timerObj.isActive && timerObj.endTime > Date() {
                        print("Found initial timer in room \(roomId): \(timerObj.id)")
                        newActiveTimers[roomId] = timerObj
                        
                        if roomId == self.currentRoomId {
                            DispatchQueue.main.async {
                                // Only post notification if this is a NEW timer
                                if self.treatmentTimer?.id != timerObj.id {
                                    self.treatmentTimer = timerObj
                                    self.treatmentTimerId = timerObj.id
                                    self.saveTimerState()
                                    NotificationCenter.default.post(
                                        name: Notification.Name("ActiveTimerFound"),
                                        object: timerObj,
                                        userInfo: ["roomId": roomId]
                                    )
                                }
                            }
                        }
                    }
                } withCancel: { error in
                    print("Failed to fetch timer for room \(roomId): \(error)")
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.activeTimers = newActiveTimers
                print("Initial active timers: \(newActiveTimers.keys)")
                self.objectWillChange.send()
            }
        }
    }
    
    func setupTimerObserversForAllRooms(roomIds: [String]) {
        let dbRef = Database.database().reference()
        
        // Only observe current room's timer to reduce overhead
        guard let currentRoomId = currentRoomId else { return }
        
        dbRef.child("rooms").child(currentRoomId).child("treatmentTimer").observe(.value) { snapshot in
            if let timerDict = snapshot.value as? [String: Any],
               let timerObj = TreatmentTimer.fromDictionary(timerDict),
               timerObj.isActive && timerObj.endTime > Date() {
                
                DispatchQueue.main.async {
                    self.activeTimers[currentRoomId] = timerObj
                    self.treatmentTimer = timerObj
                    self.treatmentTimerId = timerObj.id
                    self.saveTimerState()
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("ActiveTimerFound"),
                        object: timerObj,
                        userInfo: ["roomId": currentRoomId]
                    )
                    self.objectWillChange.send()
                }
            } else {
                DispatchQueue.main.async {
                    self.activeTimers.removeValue(forKey: currentRoomId)
                    self.treatmentTimer = nil
                    self.treatmentTimerId = nil
                    self.saveTimerState()
                    self.objectWillChange.send()
                }
            }
        } withCancel: { error in
            print("Failed to observe timer for room \(currentRoomId): \(error)")
        }
    }
    
    func setupTimerObservation() {
        if let roomId = currentRoomId {
            let dbRef = Database.database().reference()
            dbRef.child("rooms").child(roomId).child("treatmentTimer").observe(.value) { snapshot in
                if let timerDict = snapshot.value as? [String: Any],
                   let timerObj = TreatmentTimer.fromDictionary(timerDict),
                   timerObj.isActive && timerObj.endTime > Date() {
                    
                    DispatchQueue.main.async {
                        // Only update if timer is newer or we don't have one
                        if self.treatmentTimer == nil ||
                            self.treatmentTimer!.endTime < timerObj.endTime {
                            self.treatmentTimer = timerObj
                            self.treatmentTimerId = timerObj.id
                            
                            // Notify the UI
                            NotificationCenter.default.post(
                                name: Notification.Name("ActiveTimerFound"),
                                object: timerObj
                            )
                        }
                    }
                }
            }
        }
    }
    
    func switchToRoom(roomId: String) {

        guard let userId = currentUser?.id.uuidString else { return }
        logToFile("Switching to room: \(roomId) from current room: \(currentRoomId ?? "none")")
        
        let dbRef = Database.database().reference()
        
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            guard let roomAccess = snapshot.value as? [String: Any] else {
                print("No room access data found")
                return
            }
            
            if roomAccess[roomId] == nil {
                print("You no longer have access to this room")
                return
            }
            
            var updatedRoomAccess: [String: [String: Any]] = [:]
            let joinedAt = ISO8601DateFormatter().string(from: Date())
            
            for (existingRoomId, accessData) in roomAccess {
                var newAccess: [String: Any]
                
                if let accessDict = accessData as? [String: Any] {
                    newAccess = accessDict
                } else if accessData as? Bool == true {
                    newAccess = [
                        "joinedAt": joinedAt,
                        "isActive": false
                    ]
                } else {
                    continue
                }
                
                newAccess["isActive"] = existingRoomId == roomId
                updatedRoomAccess[existingRoomId] = newAccess
            }
            
            dbRef.child("users").child(userId).child("roomAccess").setValue(updatedRoomAccess) { error, _ in
                if let error = error {
                    print("Error switching rooms: \(error.localizedDescription)")
                    return
                }
                
                self.saveTimerState()
                
                let oldRoomId = self.currentRoomId
                self.currentRoomId = nil
                
                self.cycles = []
                self.cycleItems = [:]
                self.groupedItems = [:]
                self.consumptionLog = [:]
                
                DispatchQueue.main.async {
                    self.currentRoomId = roomId
                    UserDefaults.standard.set(roomId, forKey: "currentRoomId")
                    
                    self.loadRoomData(roomId: roomId)
                    
                    if let timer = self.activeTimers[roomId], timer.isActive, timer.endTime > Date() {
                        self.treatmentTimer = timer
                        self.treatmentTimerId = timer.id
                        NotificationCenter.default.post(
                            name: Notification.Name("ActiveTimerFound"),
                            object: timer,
                            userInfo: ["roomId": roomId]
                        )
                    } else {
                        self.treatmentTimer = nil
                        self.treatmentTimerId = nil
                    }
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("RoomJoined"),
                        object: nil,
                        userInfo: ["oldRoomId": oldRoomId ?? "", "newRoomId": roomId]
                    )
                    
                    // NEW: Setup Live Activity observer for new room
                    if #available(iOS 16.1, *) {
                        self.setupLiveActivityObserver()
                    }
                }
            }
        }
    }
    
    // New method to reschedule notifications for all active timers
    func rescheduleAllNotifications() {
        // This method is intentionally disabled to prevent notification interference
        // Timer notifications are handled individually when timers are created/modified
        logToFile("rescheduleAllNotifications called - method disabled for performance")
    }
    
    // Function to snooze the treatment timer
    func snoozeTreatmentTimer(duration: TimeInterval = 300, roomId: String? = nil) {
        let targetRoomId = roomId ?? currentRoomId
        guard let roomId = targetRoomId, let currentTimer = activeTimers[roomId] else { return }
        
        if let notificationIds = currentTimer.notificationIds {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
        }
        
        let endTime = Date().addingTimeInterval(duration)
        let participantName = currentTimer.roomName ?? cycles.first(where: { $0.id == currentCycleId() })?.patientName ?? "TIPs App"
        let notificationIds = scheduleNotifications(timerId: currentTimer.id, endTime: endTime, duration: duration, participantName: participantName, roomId: roomId)
        
        let newTimer = TreatmentTimer(
            id: currentTimer.id,
            isActive: true,
            endTime: endTime,
            associatedItemIds: currentTimer.associatedItemIds,
            notificationIds: notificationIds,
            roomName: participantName
        )
        
        activeTimers[roomId] = newTimer
        if roomId == currentRoomId {
            treatmentTimer = newTimer
        }
        
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("treatmentTimer").setValue(newTimer.toDictionary()) { error, _ in
            if let error = error {
                // print("Failed to update snoozed timer in Firebase for room \(roomId): \(error)")
                self.logToFile("Failed to update snoozed timer in Firebase for room \(roomId): \(error)")
            } else {
                // print("Updated snoozed timer in Firebase for room \(roomId)")
                self.logToFile("Updated snoozed timer in Firebase for room \(roomId)")
            }
        }
    }
    
    private func mergeTimerStates(local: TreatmentTimer?, firebase: TreatmentTimer?) -> TreatmentTimer? {
        switch (local, firebase) {
        case (let local?, let firebase?) where local.isActive && firebase.isActive:
            return local.endTime > firebase.endTime ? local : firebase
        case (let local?, nil) where local.isActive && local.endTime > Date():
            return local
        case (nil, let firebase?) where firebase.isActive && firebase.endTime > Date():
            return firebase
        default:
            return nil
        }
    }
    
    private func scheduleNotifications(timerId: String, endTime: Date, duration: TimeInterval, participantName: String, roomId: String) -> [String] {
        var notificationIds: [String] = []
        
        let dbRef = Database.database().reference()
        
        // Get all users in the room first
        dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { snapshot in
            guard let roomUsers = snapshot.value as? [String: Any] else {
                print("No users found in room \(roomId)")
                self.logToFile("No users found in room \(roomId)")
                return
            }
            
            // Check each user's treatment timer setting using the new structure
            for (userId, _) in roomUsers {
                dbRef.child("users").child(userId).child("roomSettings").child(roomId).child("treatmentFoodTimerEnabled").observeSingleEvent(of: .value) { userSnapshot in
                    let isEnabled = userSnapshot.value as? Bool ?? false
                    
                    if isEnabled {
                        // Schedule notification for this user
                        let notificationId = "\(timerId)_room_\(roomId)_user_\(userId)"
                        
                        let content = UNMutableNotificationContent()
                        content.title = "\(participantName): Time for next treatment food"
                        content.body = "Your 15 minute treatment food timer has ended."
                        content.sound = UNNotificationSound(named: UNNotificationSoundName("UILocalNotificationDefaultSoundName"))
                        content.categoryIdentifier = "TREATMENT_TIMER"
                        content.interruptionLevel = .timeSensitive
                        content.threadIdentifier = "treatment-timer-thread-\(timerId)"
                        content.userInfo = ["roomId": roomId, "timerId": timerId, "participantName": participantName, "userId": userId]
                        content.badge = 0
                        
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(duration, 1), repeats: false)
                        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
                        
                        UNUserNotificationCenter.current().add(request) { error in
                            if let error = error {
                                print("Error scheduling notification \(notificationId): \(error)")
                                self.logToFile("Error scheduling notification \(notificationId): \(error)")
                            } else {
                                print("Scheduled notification \(notificationId) for user \(userId) in room \(roomId) in \(duration)s")
                                self.logToFile("Scheduled notification \(notificationId) for user \(userId) in room \(roomId) in \(duration)s")
                            }
                        }
                    } else {
                        print("Notifications disabled for user \(userId) in room \(roomId)")
                        self.logToFile("Notifications disabled for user \(userId) in room \(roomId)")
                    }
                }
            }
        }
        
        // Return array of potential notification IDs (we can't know exactly which ones will be scheduled due to async nature)
        return ["\(timerId)_room_\(roomId)"]
    }
    
    func debugNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("🔔 Notification Status:")
            print("   Authorization: \(settings.authorizationStatus.rawValue)")
            print("   Alert: \(settings.alertSetting.rawValue)")
            print("   Sound: \(settings.soundSetting.rawValue)")
            print("   Badge: \(settings.badgeSetting.rawValue)")
            
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                print("   Pending notifications: \(requests.count)")
                for request in requests.prefix(5) {
                    print("     - \(request.identifier): \(request.trigger.debugDescription)")
                }
            }
        }
    }
    
    // Check timer status and update UI
    func checkTimerStatus() -> TimeInterval? {
        guard let timer = treatmentTimer, timer.isActive else { return nil }
        
        let remainingTime = timer.endTime.timeIntervalSinceNow
        
        if remainingTime <= 0 {
            // Timer expired but wasn't properly cleared
            stopTreatmentTimer()
            return nil
        }
        
        return remainingTime
    }
    
    // Check if all treatment items are logged
    // In AppData.swift, replace the checkIfAllTreatmentItemsLogged method:
    func checkIfAllTreatmentItemsLogged() {
        guard let timer = treatmentTimer, timer.isActive,
              let associatedItemIds = timer.associatedItemIds,
              !associatedItemIds.isEmpty,
              let cycleId = currentCycleId() else {
            return
        }
        
        // Get all treatment items
        let treatmentItems = (cycleItems[cycleId] ?? []).filter { $0.category == .treatment }
        
        // If there are no treatment items, stop the timer
        if treatmentItems.isEmpty {
            stopTreatmentTimer()
            return
        }
        
        // Check if all treatment items are logged
        let today = Calendar.current.startOfDay(for: Date())
        let allLogged = treatmentItems.allSatisfy { item in
            let logs = consumptionLog[cycleId]?[item.id] ?? []
            return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
        }
        
        if allLogged {
            // All items have been logged, stop the timer
            stopTreatmentTimer()
        }
    }
    
    func loadRoomData(roomId: String) {
        let dbRef = Database.database().reference()
        
        // print("Loading room data for roomId: \(roomId)")
        self.isLoading = true
        
        // Update room activity first
        updateRoomActivity()
        
        // Load room data
        dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { snapshot in
            // Check room owner's grace period status
            self.checkRoomOwnerGracePeriod(roomId: roomId)
            
            // Check for pending ownership requests
            self.checkPendingOwnershipRequests()
            guard snapshot.exists() else {
                // print("ERROR: Room \(roomId) does not exist in Firebase")
                self.syncError = "Room \(roomId) not found"
                self.isLoading = false
                self.currentRoomId = nil
                UserDefaults.standard.removeObject(forKey: "currentRoomId")
                return
            }
            
            // print("Room \(roomId) found in Firebase, updating references")
            self.dbRef = Database.database().reference().child("rooms").child(roomId)
            self.loadFromFirebase()
            
            // ADD THIS LINE HERE:
            self.loadMissedDoses()
            
            self.isLoading = false
            
            // Trigger timer check for all rooms
            self.checkForActiveTimers()

            // NEW: Setup Live Activity observer for this room
            if #available(iOS 16.1, *) {
                self.setupLiveActivityObserver()
            }
            
            // Clean up inactive rooms in background (only once per app session)
            if !UserDefaults.standard.bool(forKey: "cleanupRunThisSession") {
                UserDefaults.standard.set(true, forKey: "cleanupRunThisSession")
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) {
                    self.cleanupInactiveRooms()
                }
            }
        } withCancel: { error in
            // print("Error loading room \(roomId): \(error.localizedDescription)")
            self.syncError = "Failed to load room data: \(error.localizedDescription)"
            self.isLoading = false
            self.currentRoomId = nil
            UserDefaults.standard.removeObject(forKey: "currentRoomId")
        }
    }
    
    func optimizedItemSave(_ item: Item, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef else {
            completion(false)
            return
        }
        
        // Simplified saving that just sends this one item directly
        let itemRef = dbRef.child("cycles").child(toCycleId.uuidString).child("items").child(item.id.uuidString)
        
        // Convert item to dictionary
        let itemDict = item.toDictionary()
        
        // Save directly
        itemRef.setValue(itemDict) { error, _ in
            if let error = error {
                // print("Optimized save error: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            // Update local cache
            DispatchQueue.main.async {
                if var items = self.cycleItems[toCycleId] {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = item
                    } else {
                        items.append(item)
                    }
                    self.cycleItems[toCycleId] = items
                } else {
                    self.cycleItems[toCycleId] = [item]
                }
                completion(true)
            }
        }
    }
    
    // MARK: - Missed Dose Methods
    
    func getMissedDosesForWeek(cycleId: UUID, weekNumber: Int) -> [MissedDose] {
        guard let cycle = cycles.first(where: { $0.id == cycleId }) else { return [] }
        
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: (weekNumber - 1) * 7, to: cycle.startDate)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        
        return missedDoses[cycleId]?.filter { dose in
            dose.date >= weekStart && dose.date <= weekEnd
        } ?? []
    }

    func addMissedDose(for cycleId: UUID, on date: Date) {
        // Admin check
        guard let roomId = currentRoomId,
              (currentUser?.roomAccess?[roomId]?.isAdmin ?? false) || (currentUser?.isSuperAdmin ?? false) else {
            return
        }
        
        let missedDose = MissedDose(date: date, cycleId: cycleId)
        
        if missedDoses[cycleId] == nil {
            missedDoses[cycleId] = []
        }
        
        // Don't add duplicates for the same date
        if !missedDoses[cycleId]!.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            missedDoses[cycleId]!.append(missedDose)
            saveMissedDoses(for: cycleId)
        }
    }

    func removeMissedDose(for cycleId: UUID, on date: Date) {
        // Admin check
        guard let roomId = currentRoomId,
              (currentUser?.roomAccess?[roomId]?.isAdmin ?? false) || (currentUser?.isSuperAdmin ?? false) else {
            return
        }
        
        guard var doses = missedDoses[cycleId] else { return }
        
        doses.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        missedDoses[cycleId] = doses
        saveMissedDoses(for: cycleId)
    }

    func getMissedDosesForCurrentWeek(cycleId: UUID) -> [MissedDose] {
        guard let cycle = cycles.first(where: { $0.id == cycleId }) else { return [] }
        
        let calendar = Calendar.current
        let today = Date()
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        let currentWeekOffset = daysSinceStart / 7
        let weekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: cycle.startDate)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        
        return missedDoses[cycleId]?.filter { dose in
            dose.date >= weekStart && dose.date <= weekEnd
        } ?? []
    }

    func getTreatmentItemsForCycle(_ cycleId: UUID) -> [Item] {
        return (cycleItems[cycleId] ?? []).filter { item in
            item.category == .treatment
        }
    }

    // Modified week calculation to account for missed doses
    func adjustedCurrentWeekNumber(forCycleId cycleId: UUID?) -> Int {
        guard let cycleId = cycleId,
              let cycle = cycles.first(where: { $0.id == cycleId }) else { return 1 }
        
        let calendar = Calendar.current
        let today = Date()
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        
        // Count ALL missed doses (including current week)
        let totalMissedDoses = missedDoses[cycleId]?.count ?? 0
        
        // Adjust the effective days since start
        let adjustedDaysSinceStart = max(0, daysSinceStart - totalMissedDoses)
        return (adjustedDaysSinceStart / 7) + 1
    }

    private func getMissedDosesBeforeCurrentWeek(cycleId: UUID) -> [MissedDose] {
        guard let cycle = cycles.first(where: { $0.id == cycleId }) else { return [] }
        
        let calendar = Calendar.current
        let today = Date()
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        let currentWeekOffset = daysSinceStart / 7
        let currentWeekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: cycle.startDate)!
        
        return missedDoses[cycleId]?.filter { dose in
            dose.date < currentWeekStart
        } ?? []
    }

    // Check if a specific date has missed doses
    func hasMissedDoses(for cycleId: UUID, on date: Date) -> Bool {
        return missedDoses[cycleId]?.contains { dose in
            Calendar.current.isDate(dose.date, inSameDayAs: date)
        } ?? false
    }

    // Firebase sync methods
    private func saveMissedDoses(for cycleId: UUID) {
        guard let dbRef = dbRef, let roomId = currentRoomId else { return }
        
        let doses = missedDoses[cycleId] ?? []
        var dosesDict: [String: [String: Any]] = [:]
        
        for dose in doses {
            dosesDict[dose.id.uuidString] = [
                "id": dose.id.uuidString,
                "date": ISO8601DateFormatter().string(from: dose.date),
                "cycleId": dose.cycleId.uuidString
            ]
        }
        
        dbRef.child("rooms").child(roomId).child("cycles").child(cycleId.uuidString).child("missedDoses").setValue(dosesDict)
    }

    private func loadMissedDoses() {
        guard let dbRef = dbRef, let roomId = currentRoomId else { return }
        
        for cycle in cycles {
            dbRef.child("rooms").child(roomId).child("cycles").child(cycle.id.uuidString).child("missedDoses")
                .observeSingleEvent(of: .value) { [weak self] snapshot in
                    guard let self = self,
                          let dosesData = snapshot.value as? [String: [String: Any]] else { return }
                    
                    let doses = dosesData.compactMap { (_, doseDict) -> MissedDose? in
                        return MissedDose(dictionary: doseDict)
                    }
                    
                    DispatchQueue.main.async {
                        self.missedDoses[cycle.id] = doses
                    }
                }
        }
    }
    
    // MARK: - User Migration Function
    func migrateUserToNewStructure(user: User, completion: @escaping (User?) -> Void) {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId") else {
            completion(nil)
            return
        }
        
        let dbRef = Database.database().reference()
        let userId = user.id.uuidString
        
        // Check if user already has new structure
        if user.roomAccess != nil && user.roomSettings != nil {
            completion(user)
            return
        }
        
        print("Migrating user \(user.name) to new structure")
        
        // Get the old user data from Firebase
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
            guard let userData = snapshot.value as? [String: Any] else {
                completion(nil)
                return
            }
            
            // Extract old global properties
            let oldIsAdmin = userData["isAdmin"] as? Bool ?? false
            let oldTreatmentFoodTimer = userData["treatmentFoodTimerEnabled"] as? Bool ?? false
            let oldRemindersEnabled = userData["remindersEnabled"] as? [String: Bool] ?? [:]
            let oldReminderTimes = userData["reminderTimes"] as? [String: String] ?? [:]
            
            // Create new room-specific structures
            let roomAccess = RoomAccess(
                isActive: true,
                joinedAt: Date(),
                isAdmin: oldIsAdmin
            )
            
            // Convert old reminder data to new format
            var newRemindersEnabled: [Category: Bool] = [:]
            var newReminderTimes: [Category: Date] = [:]
            
            for (categoryString, enabled) in oldRemindersEnabled {
                if let category = Category(rawValue: categoryString) {
                    newRemindersEnabled[category] = enabled
                }
            }
            
            for (categoryString, timeString) in oldReminderTimes {
                if let category = Category(rawValue: categoryString),
                   let date = ISO8601DateFormatter().date(from: timeString) {
                    newReminderTimes[category] = date
                }
            }
            
            let roomSettings = RoomSettings(
                treatmentFoodTimerEnabled: oldTreatmentFoodTimer,
                remindersEnabled: newRemindersEnabled,
                reminderTimes: newReminderTimes
            )
            
            // Create updated user
            var updatedUser = user
            updatedUser.roomAccess = [currentRoomId: roomAccess]
            updatedUser.roomSettings = [currentRoomId: roomSettings]
            
            // Save new structure to Firebase
            let updates: [String: Any] = [
                "users/\(userId)/roomAccess/\(currentRoomId)": roomAccess.toDictionary(),
                "users/\(userId)/roomSettings/\(currentRoomId)": roomSettings.toDictionary()
            ]
            
            dbRef.updateChildValues(updates) { error, _ in
                if error == nil {
                    print("Successfully migrated user \(user.name) to new structure")
                    
                    // Remove old properties
                    let oldPropertiesToRemove = [
                        "users/\(userId)/isAdmin",
                        "users/\(userId)/treatmentFoodTimerEnabled",
                        "users/\(userId)/remindersEnabled",
                        "users/\(userId)/reminderTimes",
                        "users/\(userId)/treatmentTimerDuration"
                    ]
                    
                    for property in oldPropertiesToRemove {
                        dbRef.child(property).removeValue()
                    }
                    
                    completion(updatedUser)
                } else {
                    print("Failed to migrate user: \(error?.localizedDescription ?? "Unknown error")")
                    completion(nil)
                }
            }
        }
    }
    
    func nukeAllGroupedItems(forCycleId cycleId: UUID) {
        // print("NUKE: Starting complete group deletion for cycle \(cycleId)")
        
        // 1. Clear local memory
        groupedItems[cycleId] = []
        
        // 2. Get direct database reference
        guard let roomId = currentRoomId else {
            // print("NUKE: No current room ID, aborting")
            return
        }
        
        let mainDbRef = Database.database().reference()
        
        // 3. Directly delete at the room level
        mainDbRef.child("rooms").child(roomId).child("cycles").child(cycleId.uuidString).child("groupedItems").removeValue { error, _ in
            if let error = error {
                // print("NUKE: Failed to remove groupedItems: \(error.localizedDescription)")
            } else {
                // print("NUKE: Successfully nuked all groupedItems for cycle \(cycleId)")
            }
        }
        
        // 4. Also clear any group collapse states
        mainDbRef.child("rooms").child(roomId).child("groupCollapsed").observeSingleEvent(of: .value) { snapshot in
            if let collapseStates = snapshot.value as? [String: Bool] {
                let updates = collapseStates.mapValues { _ in NSNull() }
                mainDbRef.child("rooms").child(roomId).child("groupCollapsed").updateChildValues(updates as [String: Any])
                // print("NUKE: Cleared group collapse states")
            }
        }
    }
    
    private var pendingConsumptionLogUpdates: [UUID: [UUID: [LogEntry]]] = [:] // Track pending updates
    
    private var dbRef: DatabaseReference?
    private var isAddingCycle = false
    public var treatmentTimerId: String? {
        didSet { saveTimerState() }
    }
    
    func forceDeleteAllGroupedItems(forCycleId cycleId: UUID) {
        // Clear in memory
        groupedItems[cycleId] = []
        
        // Clear in Firebase with a forceful approach
        if let dbRef = dbRef {
            let groupedItemsRef = dbRef.child("cycles").child(cycleId.uuidString).child("groupedItems")
            
            // First read all groups to explicitly delete each one
            groupedItemsRef.observeSingleEvent(of: .value) { snapshot in
                if let groups = snapshot.value as? [String: Any] {
                    for (groupId, _) in groups {
                        groupedItemsRef.child(groupId).removeValue()
                    }
                }
                
                // Then clear the entire node
                groupedItemsRef.removeValue { error, _ in
                    if let error = error {
                        // print("Error clearing grouped items: \(error.localizedDescription)")
                    } else {
                        // print("Successfully cleared all grouped items for cycle \(cycleId)")
                    }
                }
            }
        }
    }
    
    // Functions to handle profile images
    func saveProfileImage(_ image: UIImage, forCycleId cycleId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        let fileName = "profile_\(cycleId.uuidString).jpg"
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? data.write(to: url)
            UserDefaults.standard.set(fileName, forKey: "profileImage_\(cycleId.uuidString)")
        }
    }
    
    func loadProfileImage(forCycleId cycleId: UUID) -> UIImage? {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return nil
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        
        return nil
    }
    
    func deleteProfileImage(forCycleId cycleId: UUID) {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: "profileImage_\(cycleId.uuidString)")
        }
    }
    
    
    init() {
        // // print("AppData initializing")
        logToFile("AppData initializing")
        
        // First check if we have a user ID and room ID
        if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
           let userId = UUID(uuidString: userIdStr) {
            // // print("Found existing user ID: \(userIdStr)")
            loadCurrentUserSettings(userId: userId)
            
            // Prioritize currentRoomId over roomCode
            if let roomId = UserDefaults.standard.string(forKey: "currentRoomId") {
                //    // print("Found existing room ID: \(roomId), loading room data")
                self.currentRoomId = roomId
                // Clear roomCode to avoid confusion
                UserDefaults.standard.removeObject(forKey: "roomCode")
            } else if let roomCode = UserDefaults.standard.string(forKey: "roomCode") {
                // Legacy support for old room code system
                //  // print("Using legacy room code: \(roomCode)")
                self.roomCode = roomCode
            } else {
                //  // print("No existing room found, will need setup")
            }
        } else {
            //  // print("No existing user or room found, will need setup")
        }
        
        units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
        loadCachedData()
        
        // Ensure all groups start collapsed
        for (cycleId, groups) in groupedItems {
            for group in groups {
                if groupCollapsed[group.id] == nil {
                    groupCollapsed[group.id] = true
                }
            }
        }
        
        loadTimerState()
        checkAndResetIfNeeded()
        rescheduleDailyReminders()
        
        if currentRoomId != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // print("Delayed timer check starting")
                self.checkForActiveTimers()
            }
        }
        
        // Log timer state
        // // print("AppData init: Loaded treatmentTimer = \(String(describing: treatmentTimer))")
        logToFile("AppData init: Loaded treatmentTimer = \(String(describing: treatmentTimer))")
        
        if let timer = treatmentTimer {
            if timer.isActive && timer.endTime > Date() {
                //  // print("AppData init: Active timer found, endDate = \(timer.endTime)")
                logToFile("AppData init: Active timer found, endDate = \(timer.endTime)")
            } else {
                //  // print("AppData init: Timer expired, clearing treatmentTimer")
                logToFile("AppData init: Timer expired, clearing treatmentTimer")
                self.treatmentTimer = nil
            }
        } else {
            //  // print("AppData init: No active timer to resume")
            logToFile("AppData init: No active timer to resume")
        }
        loadTimerState()
        if let timer = treatmentTimer, timer.isActive, timer.endTime > Date() {
            //  // print("AppData init: Found active timer with \(timer.endTime.timeIntervalSinceNow)s remaining")
            logToFile("AppData init: Found active timer with \(timer.endTime.timeIntervalSinceNow)s remaining")
            
            // Also check UserDefaults as a backup
            if let timerData = UserDefaults.standard.data(forKey: "treatmentTimerState") {
                do {
                    let backupState = try JSONDecoder().decode(TimerState.self, from: timerData)
                    if let backupTimer = backupState.timer,
                       backupTimer.isActive && backupTimer.endTime > Date() &&
                        backupTimer.endTime > timer.endTime {
                        // Use the backup if it's newer
                        treatmentTimer = backupTimer
                        //  // print("Using newer backup timer from UserDefaults")
                        logToFile("Using newer backup timer from UserDefaults")
                    }
                } catch {
                    //  // print("Error decoding backup timer: \(error)")
                    logToFile("Error decoding backup timer: \(error)")
                }
            }
            
            // Notify immediately on init that we have an active timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                //  // print("Posting ActiveTimerFound notification from AppData init")
                self.logToFile("Posting ActiveTimerFound notification from AppData init")
                NotificationCenter.default.post(
                    name: Notification.Name("ActiveTimerFound"),
                    object: self.treatmentTimer
                )
            }
        }
        // Add this after the existing initialization code
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.loadTransferRequests()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.cleanupExpiredTransferRequests()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.cleanupDanglingTransferRequests()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadTreatmentTimerOverride()
        }
    }
    
    func trackAppVersionForCurrentUser() {
        print("🔍 AppData: trackAppVersionForCurrentUser called")
        
        guard let currentUser = self.currentUser else {
            print("❌ AppData: No current user for version tracking")
            return
        }
        
        print("👤 AppData: Current user is \(currentUser.name) (ID: \(currentUser.id))")
        
        AppVersionTracker.shared.recordAppVersionOnLaunch(for: currentUser, appData: self)
    }
    
    func globalRefresh() {
        //  // print("Performing global data refresh")
        self.logToFile("Performing global data refresh")
        
        guard let roomId = currentRoomId else {
            // print("No current room ID, cannot refresh")
            self.isLoading = false
            NotificationCenter.default.post(name: Notification.Name("DataRefreshed"), object: nil)
            return
        }
        
        // Mark as loading
        self.isLoading = true
        
        // Get a direct reference to the database
        let dbRef = Database.database().reference()
        
        // First load cycles
        dbRef.child("rooms").child(roomId).child("cycles").observeSingleEvent(of: .value) { snapshot in
            guard snapshot.exists(), let cyclesData = snapshot.value as? [String: [String: Any]] else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    NotificationCenter.default.post(name: Notification.Name("DataRefreshed"), object: nil)
                }
                return
            }
            
            var loadedCycles: [Cycle] = []
            var loadedCycleItems: [UUID: [Item]] = [:]
            var loadedConsumptionLog: [UUID: [UUID: [LogEntry]]] = [:]
            var loadedGroupedItems: [UUID: [GroupedItem]] = [:]
            var loadedReactions: [UUID: [Reaction]] = [:]
            
            let group = DispatchGroup()
            
            // Process cycles
            for (cycleId, cycleData) in cyclesData {
                guard let cycleUUID = UUID(uuidString: cycleId) else { continue }
                
                var mutableData = cycleData
                mutableData["id"] = cycleId
                if let cycle = Cycle(dictionary: mutableData) {
                    loadedCycles.append(cycle)
                    
                    // Load items for this cycle
                    group.enter()
                    dbRef.child("rooms").child(roomId).child("cycles").child(cycleId).child("items")
                        .observeSingleEvent(of: .value) { itemsSnapshot in
                            
                            defer { group.leave() }
                            
                            if let itemsData = itemsSnapshot.value as? [String: [String: Any]] {
                                let items = itemsData.compactMap { (itemId, itemData) -> Item? in
                                    var mutableItem = itemData
                                    mutableItem["id"] = itemId
                                    return Item(dictionary: mutableItem)
                                }
                                
                                if !items.isEmpty {
                                    loadedCycleItems[cycleUUID] = items
                                }
                            }
                        }
                    
                    // Load grouped items for this cycle
                    group.enter()
                    dbRef.child("rooms").child(roomId).child("cycles").child(cycleId).child("groupedItems")
                        .observeSingleEvent(of: .value) { groupsSnapshot in
                            
                            defer { group.leave() }
                            
                            if let groupsData = groupsSnapshot.value as? [String: [String: Any]] {
                                let groups = groupsData.compactMap { (groupId, groupData) -> GroupedItem? in
                                    var mutableGroup = groupData
                                    mutableGroup["id"] = groupId
                                    return GroupedItem(dictionary: mutableGroup)
                                }
                                
                                if !groups.isEmpty {
                                    loadedGroupedItems[cycleUUID] = groups
                                }
                            }
                        }
                    
                    // Load consumption log for this cycle
                    group.enter()
                    dbRef.child("rooms").child(roomId).child("consumptionLog").child(cycleId)
                        .observeSingleEvent(of: .value) { logSnapshot in
                            
                            defer { group.leave() }
                            
                            if let logData = logSnapshot.value as? [String: [[String: String]]] {
                                var cycleLog: [UUID: [LogEntry]] = [:]
                                
                                for (itemIdString, entries) in logData {
                                    guard let itemId = UUID(uuidString: itemIdString) else { continue }
                                    
                                    let itemLogs = entries.compactMap { entry -> LogEntry? in
                                        guard
                                            let timestamp = entry["timestamp"],
                                            let dateObj = ISO8601DateFormatter().date(from: timestamp),
                                            let userIdString = entry["userId"],
                                            let userId = UUID(uuidString: userIdString)
                                        else { return nil }
                                        
                                        return LogEntry(date: dateObj, userId: userId)
                                    }
                                    
                                    if !itemLogs.isEmpty {
                                        cycleLog[itemId] = itemLogs
                                    }
                                }
                                
                                if !cycleLog.isEmpty {
                                    loadedConsumptionLog[cycleUUID] = cycleLog
                                }
                            }
                        }
                    
                    // Load reactions for this cycle
                    group.enter()
                    dbRef.child("rooms").child(roomId).child("cycles").child(cycleId).child("reactions")
                        .observeSingleEvent(of: .value) { reactionsSnapshot in
                            
                            defer { group.leave() }
                            
                            if let reactionsData = reactionsSnapshot.value as? [String: [String: Any]] {
                                let reactions = reactionsData.compactMap { (reactionId, reactionData) -> Reaction? in
                                    var mutableReaction = reactionData
                                    mutableReaction["id"] = reactionId
                                    return Reaction(dictionary: mutableReaction)
                                }
                                
                                if !reactions.isEmpty {
                                    loadedReactions[cycleUUID] = reactions
                                    //  // print("Loaded \(reactions.count) reactions for cycle \(cycleId)")
                                } else {
                                    // Even if empty, make sure we have an entry to clear any stale data
                                    loadedReactions[cycleUUID] = []
                                    // // print("No reactions found for cycle \(cycleId)")
                                }
                            } else {
                                // If no reactions node exists, make sure we have an empty array
                                loadedReactions[cycleUUID] = []
                                //  // print("No reactions node found for cycle \(cycleId)")
                            }
                        }
                }
            }
            self.loadMissedDoses()
            
            // When all data is loaded, update the app state
            group.notify(queue: .main) {
                self.cycles = loadedCycles.sorted { $0.startDate < $1.startDate }
                
                // Only update cycle items if we found some
                for (cycleId, items) in loadedCycleItems {
                    self.cycleItems[cycleId] = items
                }
                
                // Only update grouped items if we found some
                for (cycleId, groups) in loadedGroupedItems {
                    self.groupedItems[cycleId] = groups
                }
                
                // Only update consumption log if we found entries
                for (cycleId, logs) in loadedConsumptionLog {
                    self.consumptionLog[cycleId] = logs
                }
                
                // Always update reactions to ensure we have the latest data
                self.reactions = loadedReactions
                
                self.isLoading = false
                self.saveCachedData() // Save all data to local cache
                self.objectWillChange.send()
                
                // Notify all views
                NotificationCenter.default.post(name: Notification.Name("DataRefreshed"), object: nil)
                
                //  // print("Global refresh complete: \(self.cycles.count) cycles, \(self.cycleItems.count) item sets, \(self.consumptionLog.count) log sets, \(self.reactions.count) reaction sets")
            }
        }
    }
    
    func refreshDataOnTabSwitch() {
        // First notify of pending refresh
        self.objectWillChange.send()
        
        // Do a quick update of the local data models
        DispatchQueue.main.async {
            // Then do a full network refresh with slight delay
            // to allow the UI to update first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.globalRefresh()
            }
        }
    }
    
    private func loadConsumptionLogForCycle(cycleId: UUID) {
        guard let roomId = currentRoomId else { return }
        
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("consumptionLog").child(cycleId.uuidString)
            .observeSingleEvent(of: .value) { snapshot in
                
                // // print("Consumption log for cycle \(cycleId) - exists: \(snapshot.exists())")
                
                if snapshot.exists(), let logData = snapshot.value as? [String: [[String: String]]] {
                    DispatchQueue.main.async {
                        var cycleLog: [UUID: [LogEntry]] = [:]
                        
                        for (itemIdString, entries) in logData {
                            guard let itemId = UUID(uuidString: itemIdString) else { continue }
                            
                            let itemLogs = entries.compactMap { entry -> LogEntry? in
                                guard
                                    let timestamp = entry["timestamp"],
                                    let dateObj = ISO8601DateFormatter().date(from: timestamp),
                                    let userIdString = entry["userId"],
                                    let userId = UUID(uuidString: userIdString)
                                else { return nil }
                                
                                return LogEntry(date: dateObj, userId: userId)
                            }
                            
                            if !itemLogs.isEmpty {
                                cycleLog[itemId] = itemLogs
                            }
                        }
                        
                        self.consumptionLog[cycleId] = cycleLog
                        self.objectWillChange.send()
                        
                        // // print("Updated consumption log for cycle \(cycleId): \(cycleLog.count) items")
                    }
                }
            }
    }
    
    func ensureCorrectRoomReference() {
        // If we have a currentRoomId, make sure dbRef points to the right place
        if let roomId = currentRoomId {
            // // print("Ensuring database reference points to room: \(roomId)")
            dbRef = Database.database().reference().child("rooms").child(roomId)
            
            // Clear roomCode to avoid confusion
            self.roomCode = nil
            UserDefaults.standard.removeObject(forKey: "roomCode")
            
            // Also update the user's roomAccess to mark this room as active
            if let userId = currentUser?.id.uuidString {
                let dbMainRef = Database.database().reference()
                
                // First get all room access
                dbMainRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
                    if let roomAccess = snapshot.value as? [String: Any] {
                        var updatedRoomAccess: [String: [String: Any]] = [:]
                        let joinedAt = ISO8601DateFormatter().string(from: Date())
                        
                        for (existingRoomId, accessData) in roomAccess {
                            var newAccess: [String: Any]
                            
                            // Handle both old format (boolean) and new format (dictionary)
                            if let accessDict = accessData as? [String: Any] {
                                newAccess = accessDict
                            } else if accessData as? Bool == true {
                                newAccess = [
                                    "joinedAt": joinedAt,
                                    "isActive": false
                                ]
                            } else {
                                continue // Skip invalid entries
                            }
                            
                            // Set isActive based on the selected room
                            newAccess["isActive"] = existingRoomId == roomId
                            updatedRoomAccess[existingRoomId] = newAccess
                        }
                        
                        // Update roomAccess with new format
                        dbMainRef.child("users").child(userId).child("roomAccess").setValue(updatedRoomAccess) { error, _ in
                            if let error = error {
                                // // print("Error updating room access format: \(error.localizedDescription)")
                            } else {
                                //  // print("Successfully updated room access format")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func resetStateForNewRoom() {
        // Clear current data
        cycles = []
        cycleItems = [:]
        groupedItems = [:]
        consumptionLog = [:]
        categoryCollapsed = [:]
        groupCollapsed = [:]
        lastResetDate = nil
        // Do NOT clear activeTimers, treatmentTimer, or treatmentTimerId
        // // print("App state reset for new room, preserving timers")
        logToFile("App state reset for new room, preserving timers")
    }
    
    private func loadCachedData() {
        if let cycleData = UserDefaults.standard.data(forKey: "cachedCycles"),
           let decodedCycles = try? JSONDecoder().decode([Cycle].self, from: cycleData) {
            self.cycles = decodedCycles
        }
        if let itemsData = UserDefaults.standard.data(forKey: "cachedCycleItems"),
           let decodedItems = try? JSONDecoder().decode([UUID: [Item]].self, from: itemsData) {
            self.cycleItems = decodedItems
        }
        if let groupedItemsData = UserDefaults.standard.data(forKey: "cachedGroupedItems"),
           let decodedGroupedItems = try? JSONDecoder().decode([UUID: [GroupedItem]].self, from: groupedItemsData) {
            self.groupedItems = decodedGroupedItems
        }
        if let logData = UserDefaults.standard.data(forKey: "cachedConsumptionLog"),
           let decodedLog = try? JSONDecoder().decode([UUID: [UUID: [LogEntry]]].self, from: logData) {
            self.consumptionLog = decodedLog
        }
    }
    
    private func saveCachedData() {
        if let cycleData = try? JSONEncoder().encode(cycles) {
            UserDefaults.standard.set(cycleData, forKey: "cachedCycles")
        }
        if let itemsData = try? JSONEncoder().encode(cycleItems) {
            UserDefaults.standard.set(itemsData, forKey: "cachedCycleItems")
        }
        if let groupedItemsData = try? JSONEncoder().encode(groupedItems) {
            UserDefaults.standard.set(groupedItemsData, forKey: "cachedGroupedItems")
        }
        if let logData = try? JSONEncoder().encode(consumptionLog) {
            UserDefaults.standard.set(logData, forKey: "cachedConsumptionLog")
        }
        UserDefaults.standard.synchronize()
    }
    
    public func loadTimerState() {
        guard let url = timerStateURL() else {
            // // print("Failed to get timer state URL")
            self.logToFile("Failed to get timer state URL")
            return
        }
        
        do {
            // Try loading from file
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(TimerState.self, from: data)
                if let timer = state.timer, timer.isActive && timer.endTime > Date() {
                    self.treatmentTimer = timer
                    self.treatmentTimerId = timer.id
                    let timeRemaining = timer.endTime.timeIntervalSinceNow
                    //  // // print("Loaded valid timer from file with \(timeRemaining)s remaining")
                    self.logToFile("Loaded valid timer from file with \(timeRemaining)s remaining")
                    
                    // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("ActiveTimerFound"),
                            object: timer
                        )
                    }
                    return
                } else {
                    // // print("File timer is expired or inactive, checking UserDefaults")
                    self.logToFile("File timer is expired or inactive, checking UserDefaults")
                    try? FileManager.default.removeItem(at: url)
                }
            } else {
                // // print("No timer state file found at \(url.path)")
                self.logToFile("No timer state file found at \(url.path)")
            }
            
            // Fallback to UserDefaults
            if let timerData = UserDefaults.standard.data(forKey: "treatmentTimerState") {
                let state = try JSONDecoder().decode(TimerState.self, from: timerData)
                if let timer = state.timer, timer.isActive && timer.endTime > Date() {
                    self.treatmentTimer = timer
                    self.treatmentTimerId = timer.id
                    let timeRemaining = timer.endTime.timeIntervalSinceNow
                    // // print("Loaded valid timer from UserDefaults with \(timeRemaining)s remaining")
                    self.logToFile("Loaded valid timer from UserDefaults with \(timeRemaining)s remaining")
                    
                    // Post notification to update UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("ActiveTimerFound"),
                            object: timer
                        )
                    }
                } else {
                    // // print("UserDefaults timer is expired or inactive, clearing")
                    self.logToFile("UserDefaults timer is expired or inactive, clearing")
                    UserDefaults.standard.removeObject(forKey: "treatmentTimerState")
                }
            } else {
                // // print("No timer state in UserDefaults")
                self.logToFile("No timer state in UserDefaults")
            }
        } catch {
            // // print("Failed to load timer state: \(error.localizedDescription)")
            self.logToFile("Failed to load timer state: \(error.localizedDescription)")
        }
    }
    
    public func saveTimerState() {
        guard let url = timerStateURL() else { return }
        
        let now = Date()
        if let last = lastSaveTime, now.timeIntervalSince(last) < 5.0 {
            return
        }
        
        // Use background queue for file operations
        DispatchQueue.global(qos: .utility).async {
            do {
                if let timer = self.treatmentTimer, timer.isActive && timer.endTime > Date() {
                    let state = TimerState(timer: timer)
                    let data = try JSONEncoder().encode(state)
                    try data.write(to: url, options: .atomic)
                    self.lastSaveTime = now
                    
                    // Also update UserDefaults as backup (on main queue)
                    DispatchQueue.main.async {
                        UserDefaults.standard.set(data, forKey: "treatmentTimerState")
                    }
                    
                    self.logToFile("Saved active timer state ending at \(timer.endTime)")
                } else {
                    // Clean up files
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    
                    DispatchQueue.main.async {
                        UserDefaults.standard.removeObject(forKey: "treatmentTimerState")
                    }
                    
                    self.logToFile("No active timer to save")
                }
            } catch {
                self.logToFile("Failed to save timer state: \(error)")
            }
        }
    }
    
    private func timerStateURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("timer_state.json")
    }
    
    public func logToFile(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("app_log.txt")
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logEntry.data(using: .utf8)?.write(to: fileURL)
            }
        }
    }
    
    private func loadCurrentUserSettings(userId: UUID) {
        if let data = UserDefaults.standard.data(forKey: "userSettings_\(userId.uuidString)"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = user
            // // print("Loaded current user \(userId)")
            logToFile("Loaded current user \(userId)")
        }
    }
    
    private func saveCurrentUserSettings() {
        guard let user = currentUser else { return }
        UserDefaults.standard.set(user.id.uuidString, forKey: "currentUserId")
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "userSettings_\(user.id.uuidString)")
        }
        saveCachedData()
    }
    
    public func loadFromFirebase() {
        guard let dbRef = dbRef else {
            // print("ERROR: No database reference available.")
            logToFile("ERROR: No database reference available.")
            syncError = "No room code set."
            self.isLoading = false
            return
        }
        
        // print("Loading data from Firebase path: \(dbRef.description())")
        
        // First check if the cycles node exists
        dbRef.child("cycles").observeSingleEvent(of: .value) { snapshot in
            if !snapshot.exists() {
                // print("Creating empty cycles node")
                dbRef.child("cycles").setValue([:]) { error, ref in
                    if let error = error {
                        // print("Error creating cycles node: \(error.localizedDescription)")
                        self.syncError = "Failed to initialize database structure"
                    } else {
                        // print("Successfully created cycles node")
                        // Continue loading after ensuring the node exists
                        self.setupPersistentObservers()
                    }
                }
            } else {
                // Node exists, continue with regular loading
                self.setupPersistentObservers()
            }
        }
    }
    
    private func setupPersistentObservers() {
        guard let dbRef = dbRef else { return }
        
        // Observe cycles with a persistent listener
        dbRef.child("cycles").observe(.value) { snapshot in
            if self.isAddingCycle { return }
            var newCycles: [Cycle] = []
            
            if snapshot.exists(), let value = snapshot.value as? [String: [String: Any]] {
                // print("Processing \(value.count) cycles from Firebase")
                
                for (key, dict) in value {
                    var mutableDict = dict
                    mutableDict["id"] = key
                    guard let cycle = Cycle(dictionary: mutableDict) else {
                        // print("Failed to parse cycle with key: \(key)")
                        continue
                    }
                    
                    // print("Parsed cycle: \(cycle.number) - \(cycle.patientName)")
                    newCycles.append(cycle)
                    
                    // Setup observers for each cycle's data
                    self.setupCycleObservers(cycleId: key, cycleUUID: cycle.id)
                }
                
                DispatchQueue.main.async {
                    self.cycles = newCycles.sorted { $0.startDate < $1.startDate }
                    self.syncError = nil
                    self.isLoading = false
                    self.saveCachedData()
                    self.objectWillChange.send()
                    
                    // Notify views that data has been updated
                    NotificationCenter.default.post(name: Notification.Name("DataRefreshed"), object: nil)
                }
            } else {
                DispatchQueue.main.async {
                    if self.cycles.isEmpty {
                        // print("ERROR: No cycles found in Firebase or data is malformed: \(snapshot.key)")
                        self.syncError = "No cycles found in Firebase or data is malformed."
                    } else {
                        // print("No cycles in Firebase but using cached data")
                        self.syncError = nil
                    }
                    self.isLoading = false
                }
            }
        }
        
        // Observe units
        dbRef.child("units").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let units = value.compactMap { (key, dict) -> Unit? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return Unit(dictionary: mutableDict)
                }
                
                DispatchQueue.main.async {
                    if units.isEmpty {
                        // Ensure we always have at least the default units
                        if self.units.isEmpty {
                            self.units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
                        }
                    } else {
                        // Add default units if they don't exist
                        var allUnits = units
                        let defaultUnits = ["mg", "g", "tsp", "tbsp", "oz", "mL", "nuts", "fist sized"]
                        for defaultUnit in defaultUnits {
                            if !allUnits.contains(where: { $0.name == defaultUnit }) {
                                allUnits.append(Unit(name: defaultUnit))
                            }
                        }
                        self.units = allUnits
                    }
                    
                    // If we have items that reference units not in our units list, add those units
                    self.ensureItemUnitsExist()
                    
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            } else {
                // If Firebase returns no units, make sure we have at least the defaults
                DispatchQueue.main.async {
                    if self.units.isEmpty {
                        self.units = [Unit(name: "mg"), Unit(name: "g"), Unit(name: "tsp"), Unit(name: "tbsp"), Unit(name: "oz"), Unit(name: "mL"), Unit(name: "nuts"), Unit(name: "fist sized")]
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
        
        // Observe category collapse state
        dbRef.child("categoryCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    self.categoryCollapsed = value
                }
            }
        }
        
        // Observe group collapse state
        dbRef.child("groupCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    let firebaseCollapsed = value.reduce(into: [UUID: Bool]()) { result, pair in
                        if let groupId = UUID(uuidString: pair.key) {
                            result[groupId] = pair.value
                        }
                    }
                    // Merge Firebase data, preserving local changes if they exist
                    for (groupId, isCollapsed) in firebaseCollapsed {
                        if self.groupCollapsed[groupId] == nil {
                            self.groupCollapsed[groupId] = isCollapsed
                        }
                    }
                }
            }
        }
        
        // Observe users
        dbRef.child("users").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let users = value.compactMap { (key, dict) -> User? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return User(dictionary: mutableDict)
                }
                DispatchQueue.main.async {
                    self.users = users
                    if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
                       let userId = UUID(uuidString: userIdStr),
                       let updatedUser = users.first(where: { $0.id == userId }) {
                        self.currentUser = updatedUser
                        self.saveCurrentUserSettings()
                    }
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
        
        // Current user observer
        if let userId = currentUser?.id.uuidString {
            dbRef.child("users").child(userId).observe(.value) { snapshot in
                if let userData = snapshot.value as? [String: Any],
                   let user = User(dictionary: userData) {
                    DispatchQueue.main.async {
                        self.currentUser = user
                        self.saveCurrentUserSettings()
                    }
                }
            }
        }
        
        // Treatment timer observer
        dbRef.child("treatmentTimer").observe(.value) { snapshot in
            // print("Treatment timer update from Firebase at path \(dbRef.child("treatmentTimer").description()): \(String(describing: snapshot.value))")
            self.logToFile("Treatment timer update from Firebase at path \(dbRef.child("treatmentTimer").description()): \(String(describing: snapshot.value))")
            
            if let timerDict = snapshot.value as? [String: Any],
               let timerObj = TreatmentTimer.fromDictionary(timerDict) {
                
                // print("Parsed timer object: isActive=\(timerObj.isActive), endTime=\(timerObj.endTime)")
                self.logToFile("Parsed timer object: isActive=\(timerObj.isActive), endTime=\(timerObj.endTime)")
                
                // Only update if the timer is still active and has not expired
                if timerObj.isActive && timerObj.endTime > Date() {
                    DispatchQueue.main.async {
                        self.treatmentTimer = timerObj
                        self.treatmentTimerId = timerObj.id
                        // print("Updated local timer from Firebase")
                        self.logToFile("Updated local timer from Firebase")
                        
                        // Add this notification to ensure ContentView updates
                        NotificationCenter.default.post(
                            name: Notification.Name("ActiveTimerFound"),
                            object: timerObj
                        )
                    }
                } else {
                    // Timer is inactive or expired, clear it
                    DispatchQueue.main.async {
                        self.treatmentTimer = nil
                        self.treatmentTimerId = nil
                        // print("Cleared local timer (inactive or expired)")
                        self.logToFile("Cleared local timer (inactive or expired)")
                    }
                    
                    // Clean up expired timer in Firebase
                    dbRef.child("treatmentTimer").removeValue()
                }
            } else {
                // No timer in Firebase, clear local timer
                DispatchQueue.main.async {
                    if self.treatmentTimer != nil {
                        self.treatmentTimer = nil
                        self.treatmentTimerId = nil
                        // print("Cleared local timer (no timer in Firebase)")
                        self.logToFile("Cleared local timer (no timer in Firebase)")
                    }
                }
            }
        }
        // Load treatment timer override settings
        loadTreatmentTimerOverride()
    }
    
    // Setup observers for a specific cycle's data
    private func setupCycleObservers(cycleId: String, cycleUUID: UUID) {
        guard let dbRef = dbRef else { return }
        
        // Observe items for this cycle
        let itemsRef = dbRef.child("cycles").child(cycleId).child("items")
        itemsRef.observe(.value) { snapshot in
            if let itemsDict = snapshot.value as? [String: [String: Any]] {
                let items = itemsDict.compactMap { (itemId, itemData) -> Item? in
                    var mutableItem = itemData
                    mutableItem["id"] = itemId
                    return Item(dictionary: mutableItem)
                }.sorted { $0.order < $1.order }
                
                DispatchQueue.main.async {
                    self.cycleItems[cycleUUID] = items
                    self.ensureItemUnitsExist()
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            } else if self.cycleItems[cycleUUID] == nil {
                DispatchQueue.main.async {
                    self.cycleItems[cycleUUID] = []
                }
            }
        }
        
        // Observe grouped items for this cycle
        let groupedItemsRef = dbRef.child("cycles").child(cycleId).child("groupedItems")
        groupedItemsRef.observe(.value) { snapshot in
            if let groupedItemsDict = snapshot.value as? [String: [String: Any]] {
                let groupedItems = groupedItemsDict.compactMap { (groupId, groupData) -> GroupedItem? in
                    var mutableGroup = groupData
                    mutableGroup["id"] = groupId
                    return GroupedItem(dictionary: mutableGroup)
                }
                
                DispatchQueue.main.async {
                    self.groupedItems[cycleUUID] = groupedItems
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            } else if self.groupedItems[cycleUUID] == nil {
                DispatchQueue.main.async {
                    self.groupedItems[cycleUUID] = []
                }
            }
        }
        
        // Observe reactions for this cycle - CRITICAL for ensuring reactions are always up to date
        let reactionsRef = dbRef.child("cycles").child(cycleId).child("reactions")
        reactionsRef.observe(.value) { snapshot in
            // print("Reactions update for cycle \(cycleId): \(snapshot.exists() ? "exists" : "doesn't exist")")
            
            if let reactionsDict = snapshot.value as? [String: [String: Any]] {
                let reactions = reactionsDict.compactMap { (reactionId, reactionData) -> Reaction? in
                    var mutableReaction = reactionData
                    mutableReaction["id"] = reactionId
                    return Reaction(dictionary: mutableReaction)
                }
                
                DispatchQueue.main.async {
                    self.reactions[cycleUUID] = reactions
                    // print("Updated reactions for cycle \(cycleId): \(reactions.count) reactions")
                    self.saveCachedData()
                    self.objectWillChange.send()
                    NotificationCenter.default.post(name: Notification.Name("ReactionsUpdated"), object: nil)
                }
            } else {
                // Important: if there are no reactions, we need to set an empty array to clear any stale data
                DispatchQueue.main.async {
                    self.reactions[cycleUUID] = []
                    // print("Cleared reactions for cycle \(cycleId) - no reactions found")
                    self.saveCachedData()
                    self.objectWillChange.send()
                    NotificationCenter.default.post(name: Notification.Name("ReactionsUpdated"), object: nil)
                }
            }
        }
        
        // Observe missed doses for this cycle
        let missedDosesRef = dbRef.child("cycles").child(cycleId).child("missedDoses")
        missedDosesRef.observe(.value) { snapshot in
            if let missedDosesDict = snapshot.value as? [String: [String: Any]] {
                let missedDoses = missedDosesDict.compactMap { (_, doseData) -> MissedDose? in
                    return MissedDose(dictionary: doseData)
                }
                
                DispatchQueue.main.async {
                    self.missedDoses[cycleUUID] = missedDoses
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            } else {
                DispatchQueue.main.async {
                    self.missedDoses[cycleUUID] = []
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            }
        }
        
        // Observe consumption log for this cycle
        let logRef = dbRef.child("consumptionLog").child(cycleId)
        logRef.observe(.value) { snapshot in
            if snapshot.exists() {
                if let logData = snapshot.value as? [String: [[String: String]]] {
                    var cycleLog: [UUID: [LogEntry]] = [:]
                    
                    for (itemIdString, entries) in logData {
                        guard let itemId = UUID(uuidString: itemIdString) else { continue }
                        
                        let itemLogs = entries.compactMap { entry -> LogEntry? in
                            guard
                                let timestamp = entry["timestamp"],
                                let dateObj = ISO8601DateFormatter().date(from: timestamp),
                                let userIdString = entry["userId"],
                                let userId = UUID(uuidString: userIdString)
                            else { return nil }
                            
                            return LogEntry(date: dateObj, userId: userId)
                        }
                        
                        if !itemLogs.isEmpty {
                            cycleLog[itemId] = itemLogs
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.consumptionLog[cycleUUID] = cycleLog
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.consumptionLog[cycleUUID] = [:]
                    self.saveCachedData()
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    private func observeCycles() {
        guard let dbRef = dbRef else { return }
        
        dbRef.child("cycles").observe(.value) { snapshot in
            if self.isAddingCycle { return }
            var newCycles: [Cycle] = []
            
            var newCycleItems = self.cycleItems
            var newGroupedItems = self.groupedItems
            var newReactions: [UUID: [Reaction]] = [:]
            
            // print("Firebase cycles snapshot received: \(snapshot.key), childCount: \(snapshot.childrenCount)")
            self.logToFile("Firebase cycles snapshot received: \(snapshot.key), childCount: \(snapshot.childrenCount)")
            
            if snapshot.exists(), let value = snapshot.value as? [String: [String: Any]] {
                // print("Processing \(value.count) cycles from Firebase")
                
                for (key, dict) in value {
                    var mutableDict = dict
                    mutableDict["id"] = key
                    guard let cycle = Cycle(dictionary: mutableDict) else {
                        // print("Failed to parse cycle with key: \(key)")
                        continue
                    }
                    
                    // print("Parsed cycle: \(cycle.number) - \(cycle.patientName)")
                    newCycles.append(cycle)
                    
                    if let itemsDict = dict["items"] as? [String: [String: Any]], !itemsDict.isEmpty {
                        let firebaseItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.sorted { $0.order < $1.order }
                        
                        if let localItems = newCycleItems[cycle.id] {
                            var mergedItems = localItems.map { localItem in
                                if let firebaseItem = firebaseItems.first(where: { $0.id == localItem.id }) {
                                    return Item(
                                        id: localItem.id,
                                        name: firebaseItem.name,
                                        category: firebaseItem.category,
                                        dose: firebaseItem.dose,
                                        unit: firebaseItem.unit,
                                        weeklyDoses: localItem.weeklyDoses ?? firebaseItem.weeklyDoses, // Preserve local weeklyDoses
                                        order: firebaseItem.order,
                                        scheduleType: firebaseItem.scheduleType,
                                        customScheduleDays: firebaseItem.customScheduleDays,
                                        everyOtherDayStartDate: firebaseItem.everyOtherDayStartDate
                                    )
                                } else {
                                    return localItem
                                }
                            }
                            let newFirebaseItems = firebaseItems.filter { firebaseItem in
                                !mergedItems.contains(where: { mergedItem in mergedItem.id == firebaseItem.id })
                            }
                            mergedItems.append(contentsOf: newFirebaseItems)
                            newCycleItems[cycle.id] = mergedItems.sorted { $0.order < $1.order }
                        } else {
                            newCycleItems[cycle.id] = firebaseItems
                        }
                    } else if newCycleItems[cycle.id] == nil {
                        newCycleItems[cycle.id] = []
                    }
                    
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        let firebaseGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }
                        newGroupedItems[cycle.id] = firebaseGroupedItems
                    } else if newGroupedItems[cycle.id] == nil {
                        newGroupedItems[cycle.id] = []
                    }
                    
                    // Load reactions for this cycle
                    if let reactionsDict = dict["reactions"] as? [String: [String: Any]] {
                        let cycleReactions = reactionsDict.compactMap { (reactionKey, reactionDict) -> Reaction? in
                            var mutableReactionDict = reactionDict
                            mutableReactionDict["id"] = reactionKey
                            return Reaction(dictionary: mutableReactionDict)
                        }
                        
                        // print("Found \(cycleReactions.count) reactions for cycle \(cycle.id)")
                        
                        if !cycleReactions.isEmpty {
                            newReactions[cycle.id] = cycleReactions
                        }
                    } else {
                        // print("No reactions found for cycle \(cycle.id)")
                        // Make sure to clear any existing reactions for this cycle
                        newReactions[cycle.id] = []
                    }
                }
                DispatchQueue.main.async {
                    self.cycles = newCycles.sorted { $0.startDate < $1.startDate }
                    if !newCycleItems.isEmpty {
                        self.cycleItems = newCycleItems
                    }
                    if !newGroupedItems.isEmpty {
                        self.groupedItems = newGroupedItems
                    }
                    if !newReactions.isEmpty {
                        self.reactions = newReactions
                    }
                    self.saveCachedData()
                    self.syncError = nil
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    if self.cycles.isEmpty {
                        // print("ERROR: No cycles found in Firebase or data is malformed: \(snapshot.key)")
                        self.syncError = "No cycles found in Firebase or data is malformed."
                    } else {
                        // print("No cycles in Firebase but using cached data")
                        self.syncError = nil
                    }
                    self.isLoading = false
                }
            }
        } withCancel: { error in
            DispatchQueue.main.async {
                self.syncError = "Failed to sync cycles: \(error.localizedDescription)"
                self.isLoading = false
                // print("Sync error: \(error.localizedDescription)")
                self.logToFile("Sync error: \(error.localizedDescription)")
            }
        }
    }
    
    private func ensureItemUnitsExist() {
        var unitNames = Set(units.map { $0.name })
        
        // Scan all items in all cycles
        for (_, items) in cycleItems {
            for item in items {
                if let unitName = item.unit, !unitName.isEmpty, !unitNames.contains(unitName) {
                    // This item references a unit that doesn't exist in our units list
                    let newUnit = Unit(name: unitName)
                    units.append(newUnit)
                    unitNames.insert(unitName)
                    
                    // Save to Firebase if possible
                    if let dbRef = dbRef {
                        dbRef.child("units").child(newUnit.id.uuidString).setValue(newUnit.toDictionary())
                    }
                }
                
                // Also check weekly doses if present
                if let weeklyDoses = item.weeklyDoses, let unitName = item.unit, !unitName.isEmpty, !unitNames.contains(unitName) {
                    let newUnit = Unit(name: unitName)
                    units.append(newUnit)
                    unitNames.insert(unitName)
                    
                    // Save to Firebase if possible
                    if let dbRef = dbRef {
                        dbRef.child("units").child(newUnit.id.uuidString).setValue(newUnit.toDictionary())
                    }
                }
            }
        }
    }
    
    func setLastResetDate(_ date: Date) {
        guard let dbRef = dbRef else { return }
        dbRef.child("lastResetDate").setValue(ISO8601DateFormatter().string(from: date))
        lastResetDate = date
    }
    
    func setTreatmentTimerEnd(_ date: Date?) {
        guard let dbRef = dbRef else { return }
        if let date = date {
            dbRef.child("treatmentTimerEnd").setValue(ISO8601DateFormatter().string(from: date))
        } else {
            dbRef.child("treatmentTimerEnd").removeValue()
            self.treatmentTimerId = nil
        }
    }
    
    func addUnit(_ unit: Unit) {
        guard let dbRef = dbRef else { return }
        
        // Check if unit already exists with same name to avoid duplicates
        if !units.contains(where: { $0.name == unit.name }) {
            // Add to local array
            units.append(unit)
            
            // Save to Firebase
            dbRef.child("units").child(unit.id.uuidString).setValue(unit.toDictionary())
            
            // Save to cache for offline use
            saveCachedData()
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func addItem(_ item: Item, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef else {
            completion(false)
            return
        }
        
        // Check if cycle exists locally (important for cycle setup)
        guard cycles.contains(where: { $0.id == toCycleId }) else {
            print("Error: Cycle \(toCycleId) not found in local cycles")
            completion(false)
            return
        }
        
        // For admin check, allow if user is admin OR if we're in setup mode (no room users yet)
        if let roomId = currentRoomId, let userId = currentUser?.id.uuidString {
            let isAdmin = currentUser?.roomAccess?[roomId]?.isAdmin == true
            let isSuperAdmin = currentUser?.isSuperAdmin == true
            
            if !isAdmin && !isSuperAdmin {
                // Check if room has any users yet (setup mode)
                dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
                    if let usersData = snapshot.value as? [String: [String: Any]] {
                        let roomUsers = usersData.filter { (_, userData) in
                            if let roomAccess = userData["roomAccess"] as? [String: Any] {
                                return roomAccess[roomId] != nil
                            }
                            return false
                        }
                        
                        // If no other users in room, allow (setup mode)
                        if roomUsers.count <= 1 {
                            self.performAddItem(item, toCycleId: toCycleId, completion: completion)
                        } else {
                            completion(false)
                        }
                    } else {
                        // No users data, allow (setup mode)
                        self.performAddItem(item, toCycleId: toCycleId, completion: completion)
                    }
                }
                return
            }
        }
        
        // User is admin or super admin, proceed
        performAddItem(item, toCycleId: toCycleId, completion: completion)
    }

    private func performAddItem(_ item: Item, toCycleId: UUID, completion: @escaping (Bool) -> Void) {
        guard let dbRef = dbRef else {
            completion(false)
            return
        }
        
        // Debug print to track item data
        print("Saving item to Firebase: \(item.name), weeklyDoses: \(item.weeklyDoses?.description ?? "none")")
        
        let currentItems = cycleItems[toCycleId] ?? []
        let newOrder = item.order == 0 ? currentItems.count : item.order
        let updatedItem = Item(
            id: item.id,
            name: item.name,
            category: item.category,
            dose: item.dose,
            unit: item.unit,
            weeklyDoses: item.weeklyDoses,
            order: newOrder,
            scheduleType: item.scheduleType,
            customScheduleDays: item.customScheduleDays,
            everyOtherDayStartDate: item.everyOtherDayStartDate
        )
        let itemRef = dbRef.child("cycles").child(toCycleId.uuidString).child("items").child(updatedItem.id.uuidString)
        
        // Convert weekly doses to the correct format for Firebase
        var itemDict = updatedItem.toDictionary()
        
        // If there are weekly doses, ensure they're in the right format for Firebase
        if let weeklyDoses = item.weeklyDoses, !weeklyDoses.isEmpty {
            var weeklyDosesDict: [String: [String: Any]] = [:]
            
            for (week, doseData) in weeklyDoses {
                weeklyDosesDict[String(week)] = [
                    "dose": doseData.dose,
                    "unit": doseData.unit
                ]
            }
            
            // Replace the weeklyDoses in the dictionary
            itemDict["weeklyDoses"] = weeklyDosesDict
        }
        
        // Log the exact dictionary being saved
        print("Firebase item dictionary: \(itemDict)")
        
        itemRef.setValue(itemDict) { error, _ in
            if let error = error {
                print("Error adding item \(updatedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding item \(updatedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                print("Successfully saved item to Firebase: \(updatedItem.name)")
                DispatchQueue.main.async {
                    if var items = self.cycleItems[toCycleId] {
                        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                            items[index] = updatedItem
                        } else {
                            items.append(updatedItem)
                        }
                        self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    } else {
                        self.cycleItems[toCycleId] = [updatedItem]
                    }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }
    
    // Add this to the AppData class
    func refreshItemsFromFirebase(forCycleId cycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef else {
            completion(false)
            return
        }
        
        dbRef.child("cycles").child(cycleId.uuidString).child("items").observeSingleEvent(of: .value) { snapshot in
            if let items = snapshot.value as? [String: [String: Any]] {
                let refreshedItems = items.compactMap { (key, dict) -> Item? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return Item(dictionary: mutableDict)
                }
                
                DispatchQueue.main.async {
                    self.cycleItems[cycleId] = refreshedItems
                    self.objectWillChange.send()
                    completion(true)
                }
            } else {
                completion(false)
            }
        }
    }
    
    func saveItems(_ items: [Item], toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }) else {
            completion(false)
            return
        }
        let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
        dbRef.child("cycles").child(toCycleId.uuidString).child("items").setValue(itemsDict) { error, _ in
            if let error = error {
                // print("Error saving items to Firebase: \(error)")
                self.logToFile("Error saving items to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }
    
    func itemDisplayText(item: Item, week: Int? = nil) -> String {
        let targetWeek = week ?? currentWeekNumber(forCycleId: currentCycleId())
        let baseDisplayText: String
        
        // For treatment AND medicine items with weekly doses
        if (item.category == .treatment || item.category == .medicine), let weeklyDoses = item.weeklyDoses {
            // Try the target week first
            let doseKey = targetWeek + 1
            if let doseData = weeklyDoses[doseKey] {
                let doseText = formatDose(doseData.dose)
                baseDisplayText = "\(item.name) - \(doseText) \(doseData.unit) (Week \(targetWeek))"
            }
            // If target week not found, look for closest smaller week
            else if let availableWeeks = weeklyDoses.keys.sorted().last(where: { $0 <= doseKey }),
                    let doseData = weeklyDoses[availableWeeks] {
                let doseText = formatDose(doseData.dose)
                let displayWeek = availableWeeks - 1
                baseDisplayText = "\(item.name) - \(doseText) \(doseData.unit) (Week \(displayWeek))"
            }
            // If no smaller week, try the smallest week available
            else if let firstWeek = weeklyDoses.keys.min(), let doseData = weeklyDoses[firstWeek] {
                let doseText = formatDose(doseData.dose)
                let displayWeek = firstWeek - 1
                baseDisplayText = "\(item.name) - \(doseText) \(doseData.unit) (Week \(displayWeek))"
            } else {
                baseDisplayText = item.name
            }
        }
        // For regular items with fixed dose
        else if let dose = item.dose, let unit = item.unit {
            let doseText = formatDose(dose)
            baseDisplayText = "\(item.name) - \(doseText) \(unit)"
        } else {
            baseDisplayText = item.name
        }
        
        // Add schedule info if present
        if let scheduleText = getScheduleDisplayText(item) {
            return "\(baseDisplayText) • \(scheduleText)"
        }
        return baseDisplayText
    }
    
    // Helper method to get the current week number for a cycle
    func currentWeekNumber(forCycleId cycleId: UUID?) -> Int {
        guard let cycleId = cycleId,
              let cycle = cycles.first(where: { $0.id == cycleId }) else { return 1 }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
        return (daysSinceStart / 7) + 1
    }
    
    func getWeeklyDoseKey(forCycleId cycleId: UUID?) -> Int {
        return currentWeekNumber(forCycleId: cycleId) + 1
    }
    
    // MARK: - Scheduling Helper Methods

    // Core logic determining if item should appear on given day
    func isItemScheduledForDate(_ item: Item, _ date: Date) -> Bool {
        // Default behavior (backward compatibility)
        guard let scheduleType = item.scheduleType else { return true }
        
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // 1=Sunday, 2=Monday, etc.
        
        switch scheduleType {
        case .everyday:
            return true
            
        case .everyOtherDay:
            // Use cycle start date or everyOtherDayStartDate as reference
            let startDate: Date
            if let customStartDate = item.everyOtherDayStartDate {
                startDate = customStartDate
            } else if let cycle = cycles.first(where: { cycle in
                // Find the cycle this item belongs to
                cycleItems[cycle.id]?.contains(where: { $0.id == item.id }) == true
            }) {
                startDate = cycle.startDate
            } else {
                // Fallback to today (shouldn't happen in normal use)
                startDate = date
            }
            
            let daysSinceStart = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
            return daysSinceStart % 2 == 0
            
        case .custom:
            guard let customDays = item.customScheduleDays, !customDays.isEmpty else {
                return true // Fallback to everyday if no custom days set
            }
            return customDays.contains(weekday)
        }
    }

    // Count scheduled days in a week for progress calculation
    func scheduledDaysInWeek(_ item: Item, _ weekStart: Date) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        for dayOffset in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) {
                if isItemScheduledForDate(item, dayDate) {
                    count += 1
                }
            }
        }
        
        return count
    }

    // Human-readable schedule description for UI
    func getScheduleDisplayText(_ item: Item) -> String? {
        guard let scheduleType = item.scheduleType else { return nil }
        
        switch scheduleType {
        case .everyday:
            return nil // Don't show anything for default behavior
            
        case .everyOtherDay:
            return "Every other day"
            
        case .custom:
            guard let customDays = item.customScheduleDays, !customDays.isEmpty else {
                return nil
            }
            
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let sortedDays = customDays.sorted()
            
            // Check for common patterns
            if customDays == Set([2, 3, 4, 5, 6]) { // Monday-Friday
                return "Weekdays only"
            } else if customDays == Set([1, 7]) { // Sunday, Saturday
                return "Weekends only"
            } else if sortedDays.count <= 3 {
                // Show individual days for 3 or fewer
                let dayStrings = sortedDays.map { dayNames[$0 - 1] }
                return dayStrings.joined(separator: ", ")
            } else {
                // Show count for more than 3 days
                return "\(sortedDays.count) days per week"
            }
        }
    }

    // Helper to get expected weekly count for progress calculation
    func expectedWeeklyCount(_ item: Item) -> Int {
        // For items with schedules, calculate based on actual scheduled days
        if item.scheduleType != nil {
            let today = Date()
            let calendar = Calendar.current
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            return scheduledDaysInWeek(item, weekStart)
        }
        
        // Default behavior: 7 days per week
        return 7
    }
    
    private func formatDose(_ dose: Double) -> String {
        if dose == 1.0 {
            return "1"
        } else if let fraction = Fraction.fractionForDecimal(dose) {
            return fraction.displayString
        } else if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%d", Int(dose))
        }
        return String(format: "%.1f", dose)
    }
    
    func removeItem(_ itemId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }),
              let roomId = currentRoomId,
              currentUser?.roomAccess?[roomId]?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("items").child(itemId.uuidString).removeValue()
        if var items = cycleItems[fromCycleId] {
            items.removeAll { $0.id == itemId }
            cycleItems[fromCycleId] = items
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func addCycle(_ cycle: Cycle, copyItemsFromCycleId: UUID? = nil) {
        guard let dbRef = dbRef,
              let roomId = currentRoomId,
              currentUser?.roomAccess?[roomId]?.isAdmin == true else { return }
        
        // print("Adding cycle \(cycle.id) with number \(cycle.number)")
        
        if cycles.contains(where: { $0.id == cycle.id }) {
            // print("Cycle \(cycle.id) already exists, updating")
            saveCycleToFirebase(cycle, withItems: cycleItems[cycle.id] ?? [], groupedItems: groupedItems[cycle.id] ?? [], previousCycleId: copyItemsFromCycleId)
            return
        }
        
        isAddingCycle = true
        cycles.append(cycle)
        var copiedItems: [Item] = []
        var copiedGroupedItems: [GroupedItem] = []
        
        let effectiveCopyId = copyItemsFromCycleId ?? (cycles.count > 1 ? cycles[cycles.count - 2].id : nil)
        
        if let fromCycleId = effectiveCopyId {
            dbRef.child("cycles").child(fromCycleId.uuidString).observeSingleEvent(of: .value) { snapshot in
                if let dict = snapshot.value as? [String: Any] {
                    if let itemsDict = dict["items"] as? [String: [String: Any]] {
                        copiedItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.map { Item(id: UUID(), name: $0.name, category: $0.category, dose: $0.dose, unit: $0.unit, weeklyDoses: $0.weeklyDoses, order: $0.order, scheduleType: $0.scheduleType, customScheduleDays: $0.customScheduleDays, everyOtherDayStartDate: $0.everyOtherDayStartDate) }
                    }
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        copiedGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }.map { GroupedItem(id: UUID(), name: $0.name, category: $0.category, itemIds: $0.itemIds.map { _ in UUID() }) }
                    }
                }
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            } withCancel: { error in
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            }
        } else {
            cycleItems[cycle.id] = []
            groupedItems[cycle.id] = []
            saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
        }
    }
    
    private func saveCycleToFirebase(_ cycle: Cycle, withItems items: [Item], groupedItems: [GroupedItem], previousCycleId: UUID?) {
        guard let dbRef = dbRef else { return }
        var cycleDict = cycle.toDictionary()
        let cycleRef = dbRef.child("cycles").child(cycle.id.uuidString)
        
        cycleRef.updateChildValues(cycleDict) { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    if let index = self.cycles.firstIndex(where: { $0.id == cycle.id }) {
                        self.cycles.remove(at: index)
                        self.cycleItems.removeValue(forKey: cycle.id)
                        self.groupedItems.removeValue(forKey: cycle.id)
                    }
                    self.isAddingCycle = false
                    self.objectWillChange.send()
                }
                return
            }
            
            if !items.isEmpty {
                let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("items").updateChildValues(itemsDict)
            }
            
            if !groupedItems.isEmpty {
                let groupedItemsDict = Dictionary(uniqueKeysWithValues: groupedItems.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("groupedItems").updateChildValues(groupedItemsDict)
            }
            
            if let prevId = previousCycleId, let prevItems = self.cycleItems[prevId], !prevItems.isEmpty {
                let prevCycleRef = dbRef.child("cycles").child(prevId.uuidString)
                prevCycleRef.child("items").observeSingleEvent(of: .value) { snapshot in
                    if snapshot.value == nil || (snapshot.value as? [String: [String: Any]])?.isEmpty ?? true {
                        let prevItemsDict = Dictionary(uniqueKeysWithValues: prevItems.map { ($0.id.uuidString, $0.toDictionary()) })
                        prevCycleRef.child("items").updateChildValues(prevItemsDict)
                    }
                }
            }
            
            DispatchQueue.main.async {
                if self.cycleItems[cycle.id] == nil || self.cycleItems[cycle.id]!.isEmpty {
                    self.cycleItems[cycle.id] = items
                }
                if self.groupedItems[cycle.id] == nil || self.groupedItems[cycle.id]!.isEmpty {
                    self.groupedItems[cycle.id] = groupedItems
                }
                self.saveCachedData()
                self.isAddingCycle = false
                self.objectWillChange.send()
            }
        }
    }
    
    func addUser(_ user: User) {
        guard let dbRef = dbRef else { return }
        // print("Adding/updating user: \(user.id) with name: \(user.name)")
        
        // Update local state immediately
        DispatchQueue.main.async {
            if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                self.users[index] = user
            } else {
                self.users.append(user)
            }
            if self.currentUser?.id == user.id {
                self.currentUser = user
                self.lastUserNameUpdate = Date()
                // print("DEBUG: Set local currentUser.name to: \(user.name)")
            }
            self.saveCurrentUserSettings()
        }
        
        let userRef = dbRef.child("users").child(user.id.uuidString)
        var userDict = user.toDictionary()
        
        // Add authId if available
        if let authId = Auth.auth().currentUser?.uid {
            userDict["authId"] = authId
        }
        
        // print("DEBUG: About to update Firebase with name: \(userDict["name"] ?? "MISSING NAME")")
        
        // print("DEBUG: About to update Firebase with name: \(userDict["name"] ?? "MISSING NAME")")
        
        // Update main user node with more reliable method
        let mainDbRef = Database.database().reference()
        let mainUserRef = mainDbRef.child("users").child(user.id.uuidString)
        
        mainUserRef.updateChildValues(userDict) { error, _ in
            if let error = error {
                // print("Error adding/updating user \(user.id): \(error)")
                self.logToFile("Error adding/updating user \(user.id): \(error)")
            } else {
                // print("Successfully added/updated user \(user.id) with name: \(user.name)")
                
                // Track app version when user is successfully updated
                if self.currentUser?.id == user.id {
                    self.trackAppVersionForCurrentUser()
                }
                
                // Verify the main user update worked
                mainUserRef.child("name").observeSingleEvent(of: .value) { snapshot in
                    if let updatedName = snapshot.value as? String {
                        // print("DEBUG: Main user node verification - name is now: \(updatedName)")
                    } else {
                        // print("DEBUG: Main user node verification FAILED - could not read name")
                    }
                }
                
                // ALSO update the user in the current room's users collection
                if let roomId = self.currentRoomId {
                    let roomUserRef = mainDbRef.child("rooms").child(roomId).child("users").child(user.id.uuidString)
                    
                    let isAdmin = user.roomAccess?[roomId]?.isAdmin ?? false
                    let roomUserData = [
                        "name": user.name,
                        "isAdmin": isAdmin,
                        "joinedAt": ISO8601DateFormatter().string(from: Date())
                    ] as [String: Any]
                    
                    roomUserRef.updateChildValues(roomUserData) { roomError, _ in
                        if let roomError = roomError {
                            // print("ERROR: Failed to update room user: \(roomError)")
                        } else {
                            // print("DEBUG: Successfully updated room user with name: \(user.name)")
                        }
                    }
                }
                
                // Extend the protection window after successful Firebase update
                DispatchQueue.main.async {
                    self.lastUserNameUpdate = Date()
                    // print("DEBUG: Extended protection window at: \(Date())")
                }
            }
        }
    }
    
    func syncRoomAccess() {
        let dbRef = Database.database().reference()
        dbRef.child("rooms").observeSingleEvent(of: .value) { snapshot in
            guard let rooms = snapshot.value as? [String: [String: Any]] else { return }
            for (roomId, roomData) in rooms {
                if let roomUsers = roomData["users"] as? [String: [String: Any]] {
                    for (userId, _) in roomUsers {
                        dbRef.child("users").child(userId).child("roomAccess").child(roomId).observeSingleEvent(of: .value) { userSnapshot in
                            if !userSnapshot.exists() {
                                let joinedAt = ISO8601DateFormatter().string(from: Date())
                                dbRef.child("users").child(userId).child("roomAccess").child(roomId).setValue([
                                    "joinedAt": joinedAt,
                                    "isActive": roomId == self.currentRoomId
                                ])
                            }
                        }
                    }
                }
            }
        }
    }
    
    func migrateRoomAccess() {
        guard let userId = currentUser?.id.uuidString else { return }
        let dbRef = Database.database().reference()
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            guard let roomAccess = snapshot.value as? [String: Any] else { return }
            
            var updatedRoomAccess: [String: [String: Any]] = [:]
            let joinedAt = ISO8601DateFormatter().string(from: Date())
            
            for (roomId, accessData) in roomAccess {
                if let accessDict = accessData as? [String: Any] {
                    updatedRoomAccess[roomId] = accessDict
                } else if accessData as? Bool == true {
                    updatedRoomAccess[roomId] = [
                        "joinedAt": joinedAt,
                        "isActive": roomId == self.currentRoomId
                    ]
                }
            }
            
            dbRef.child("users").child(userId).child("roomAccess").setValue(updatedRoomAccess) { error, _ in
                if let error = error {
                    // print("Error migrating roomAccess: \(error.localizedDescription)")
                } else {
                    // print("Successfully migrated roomAccess for user \(userId)")
                }
            }
        }
    }
    
    func logConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let today = Calendar.current.startOfDay(for: Date())
        
        // Fetch current Firebase state first
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            
            // Remove any existing log for today to prevent duplicates
            currentLogs.removeAll { entry in
                if let logTimestamp = entry["timestamp"],
                   let logDate = formatter.date(from: logTimestamp) {
                    return Calendar.current.isDate(logDate, inSameDayAs: today)
                }
                return false
            }
            
            // Add the new entry
            currentLogs.append(newEntryDict)
            
            // Write to Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(currentLogs) { error, _ in
                if let error = error {
                    // print("Failed to log consumption for \(itemId): \(error)")
                    self.logToFile("Failed to log consumption for \(itemId): \(error)")
                } else {
                    // Update local consumptionLog only after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            var itemLogs = cycleLog[itemId] ?? []
                            // Remove today's existing logs locally
                            itemLogs.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
                            itemLogs.append(logEntry)
                            cycleLog[itemId] = itemLogs
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        // Clear pending updates for this item
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func removeConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        
        // Update local consumptionLog
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        // Update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                entries.removeAll { $0["timestamp"] == timestamp }
                dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries.isEmpty ? nil : entries) { error, _ in
                    if let error = error {
                        // print("Failed to remove consumption for \(itemId): \(error)")
                        self.logToFile("Failed to remove consumption for \(itemId): \(error)")
                    }
                }
            }
        }
    }
    
    func setConsumptionLog(itemId: UUID, cycleId: UUID, entries: [LogEntry]) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let newEntries = Array(Set(entries)) // Deduplicate entries
        
        // print("Setting consumption log for item \(itemId) in cycle \(cycleId) with entries: \(newEntries.map { $0.date })")
        
        // Fetch existing logs and update
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var existingEntries = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDicts = newEntries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
            
            // Remove any existing entries not in the new list to prevent retaining old logs
            existingEntries = existingEntries.filter { existingEntry in
                guard let timestamp = existingEntry["timestamp"],
                      let date = formatter.date(from: timestamp) else { return false }
                return newEntries.contains { $0.date == date && $0.userId.uuidString == existingEntry["userId"] }
            }
            
            // Add new entries
            for newEntry in newEntryDicts {
                if !existingEntries.contains(where: { $0["timestamp"] == newEntry["timestamp"] && $0["userId"] == newEntry["userId"] }) {
                    existingEntries.append(newEntry)
                }
            }
            
            // Update local consumptionLog
            if var cycleLog = self.consumptionLog[cycleId] {
                cycleLog[itemId] = newEntries
                self.consumptionLog[cycleId] = cycleLog.isEmpty ? nil : cycleLog
            } else {
                self.consumptionLog[cycleId] = [itemId: newEntries]
            }
            if self.pendingConsumptionLogUpdates[cycleId] == nil {
                self.pendingConsumptionLogUpdates[cycleId] = [:]
            }
            self.pendingConsumptionLogUpdates[cycleId]![itemId] = newEntries
            self.saveCachedData()
            
            // print("Updating Firebase with: \(existingEntries)")
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(existingEntries.isEmpty ? nil : existingEntries) { error, _ in
                DispatchQueue.main.async {
                    if let error = error {
                        // print("Failed to set consumption log for \(itemId): \(error)")
                        self.logToFile("Failed to set consumption log for \(itemId): \(error)")
                        self.syncError = "Failed to sync log: \(error.localizedDescription)"
                    } else {
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        // print("Firebase update complete, local log: \(self.consumptionLog[cycleId]?[itemId] ?? [])")
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func setCategoryCollapsed(_ category: Category, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        categoryCollapsed[category.rawValue] = isCollapsed
        dbRef.child("categoryCollapsed").child(category.rawValue).setValue(isCollapsed)
    }
    
    func setGroupCollapsed(_ groupId: UUID, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        groupCollapsed[groupId] = isCollapsed
        dbRef.child("groupCollapsed").child(groupId.uuidString).setValue(isCollapsed)
    }
    
    func setReminderEnabled(_ category: Category, enabled: Bool) {
        guard var user = currentUser, let roomId = currentRoomId else { return }
        
        // Update room settings
        var roomSettings = user.roomSettings?[roomId] ?? RoomSettings(treatmentFoodTimerEnabled: false)
        var remindersEnabled = roomSettings.remindersEnabled
        remindersEnabled[category] = enabled
        roomSettings = RoomSettings(
            treatmentFoodTimerEnabled: roomSettings.treatmentFoodTimerEnabled,
            remindersEnabled: remindersEnabled,
            reminderTimes: roomSettings.reminderTimes
        )
        
        if user.roomSettings == nil {
            user.roomSettings = [:]
        }
        user.roomSettings![roomId] = roomSettings
        
        // Update locally first for immediate UI response
        self.currentUser = user
        
        // Then save to Firebase
        addUser(user)
    }

    func setReminderTime(_ category: Category, time: Date) {
        guard var user = currentUser, let roomId = currentRoomId else { return }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        let now = Date()
        var normalizedComponents = calendar.dateComponents([.year, .month, .day], from: now)
        normalizedComponents.hour = hour
        normalizedComponents.minute = minute
        normalizedComponents.second = 0
        if let normalizedTime = calendar.date(from: normalizedComponents) {
            // Update room settings
            var roomSettings = user.roomSettings?[roomId] ?? RoomSettings(treatmentFoodTimerEnabled: false)
            var reminderTimes = roomSettings.reminderTimes
            reminderTimes[category] = normalizedTime
            roomSettings = RoomSettings(
                treatmentFoodTimerEnabled: roomSettings.treatmentFoodTimerEnabled,
                remindersEnabled: roomSettings.remindersEnabled,
                reminderTimes: reminderTimes
            )
            
            if user.roomSettings == nil {
                user.roomSettings = [:]
            }
            user.roomSettings![roomId] = roomSettings
            
            // Update locally first for immediate UI response
            self.currentUser = user
            
            // Then save to Firebase
            addUser(user)
        }
    }

    func setTreatmentFoodTimerEnabled(_ enabled: Bool) {
        guard var user = currentUser, let roomId = currentRoomId else { return }
        
        // Update room settings
        var roomSettings = user.roomSettings?[roomId] ?? RoomSettings(treatmentFoodTimerEnabled: false)
        roomSettings = RoomSettings(
            treatmentFoodTimerEnabled: enabled,
            remindersEnabled: roomSettings.remindersEnabled,
            reminderTimes: roomSettings.reminderTimes
        )
        
        if user.roomSettings == nil {
            user.roomSettings = [:]
        }
        user.roomSettings![roomId] = roomSettings
        
        // Update locally first for immediate UI response
        self.currentUser = user
        
        // Then save to Firebase
        addUser(user)
    }

    func setTreatmentTimerDuration(_ duration: TimeInterval) {
        // Treatment timer duration is now hardcoded to 900 seconds
        // This method is kept for compatibility but doesn't need to do anything
    }
    
    func addGroupedItem(_ groupedItem: GroupedItem, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }) else {
            completion(false)
            return
        }
        
        // Allow during setup mode (same logic as addItem)
        if let roomId = currentRoomId, let userId = currentUser?.id.uuidString {
            let isAdmin = currentUser?.roomAccess?[roomId]?.isAdmin == true
            let isSuperAdmin = currentUser?.isSuperAdmin == true
            
            if !isAdmin && !isSuperAdmin {
                // Check if room has any users yet (setup mode)
                dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
                    if let usersData = snapshot.value as? [String: [String: Any]] {
                        let roomUsers = usersData.filter { (_, userData) in
                            if let roomAccess = userData["roomAccess"] as? [String: Any] {
                                return roomAccess[roomId] != nil
                            }
                            return false
                        }
                        
                        // If no other users in room, allow (setup mode)
                        if roomUsers.count <= 1 {
                            self.performAddGroupedItem(groupedItem, toCycleId: toCycleId, completion: completion)
                        } else {
                            completion(false)
                        }
                    } else {
                        // No users data, allow (setup mode)
                        self.performAddGroupedItem(groupedItem, toCycleId: toCycleId, completion: completion)
                    }
                }
                return
            }
        }
        
        // User is admin or super admin, proceed
        performAddGroupedItem(groupedItem, toCycleId: toCycleId, completion: completion)
    }

    private func performAddGroupedItem(_ groupedItem: GroupedItem, toCycleId: UUID, completion: @escaping (Bool) -> Void) {
        guard let dbRef = dbRef else {
            completion(false)
            return
        }
        
        let groupRef = dbRef.child("cycles").child(toCycleId.uuidString).child("groupedItems").child(groupedItem.id.uuidString)
        groupRef.setValue(groupedItem.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    var cycleGroups = self.groupedItems[toCycleId] ?? []
                    if let index = cycleGroups.firstIndex(where: { $0.id == groupedItem.id }) {
                        cycleGroups[index] = groupedItem
                    } else {
                        cycleGroups.append(groupedItem)
                    }
                    self.groupedItems[toCycleId] = cycleGroups
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }
    
    func removeGroupedItem(_ groupId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }),
              let roomId = currentRoomId,
              currentUser?.roomAccess?[roomId]?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("groupedItems").child(groupId.uuidString).removeValue()
        if var groups = groupedItems[fromCycleId] {
            groups.removeAll { $0.id == groupId }
            groupedItems[fromCycleId] = groups
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    func logGroupedItem(_ groupedItem: GroupedItem, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef else { return }
        let today = Calendar.current.startOfDay(for: date)
        let isChecked = groupedItem.itemIds.allSatisfy { itemId in
            self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false
        }
        
        // print("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        self.logToFile("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        
        if isChecked {
            for itemId in groupedItem.itemIds {
                if let logs = self.consumptionLog[cycleId]?[itemId], !logs.isEmpty {
                    // print("Clearing all \(logs.count) logs for item \(itemId)")
                    self.logToFile("Clearing all \(logs.count) logs for item \(itemId)")
                    if var itemLogs = self.consumptionLog[cycleId] {
                        itemLogs[itemId] = []
                        if itemLogs[itemId]?.isEmpty ?? true {
                            itemLogs.removeValue(forKey: itemId)
                        }
                        self.consumptionLog[cycleId] = itemLogs.isEmpty ? nil : itemLogs
                    }
                    let path = "consumptionLog/\(cycleId.uuidString)/\(itemId.uuidString)"
                    dbRef.child(path).removeValue { error, _ in
                        if let error = error {
                            // print("Failed to clear logs for \(itemId): \(error)")
                            self.logToFile("Failed to clear logs for \(itemId): \(error)")
                        } else {
                            // print("Successfully cleared logs for \(itemId) in Firebase")
                            self.logToFile("Successfully cleared logs for \(itemId) in Firebase")
                        }
                    }
                }
            }
        } else {
            for itemId in groupedItem.itemIds {
                if !(self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false) {
                    // print("Logging item \(itemId) for \(date)")
                    self.logToFile("Logging item \(itemId) for \(date)")
                    self.logConsumption(itemId: itemId, cycleId: cycleId, date: date)
                }
            }
        }
        self.saveCachedData()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func resetDaily() {
        let today = Calendar.current.startOfDay(for: Date())
        setLastResetDate(today)
        
        for (cycleId, itemLogs) in consumptionLog {
            var updatedItemLogs = itemLogs
            for (itemId, logs) in itemLogs {
                updatedItemLogs[itemId] = logs.filter { !Calendar.current.isDate($0.date, inSameDayAs: today) }
                if updatedItemLogs[itemId]?.isEmpty ?? false {
                    updatedItemLogs.removeValue(forKey: itemId)
                }
            }
            if let dbRef = dbRef {
                let formatter = ISO8601DateFormatter()
                let updatedLogDict = updatedItemLogs.mapValues { entries in
                    entries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
                }
                dbRef.child("consumptionLog").child(cycleId.uuidString).setValue(updatedLogDict.isEmpty ? nil : updatedLogDict)
            }
            consumptionLog[cycleId] = updatedItemLogs.isEmpty ? nil : updatedItemLogs
        }
        
        Category.allCases.forEach { category in
            setCategoryCollapsed(category, isCollapsed: false)
        }
        
        if let timer = treatmentTimer, timer.isActive, timer.endTime > Date() {
            // print("Preserving active timer ending at: \(timer.endTime)")
            logToFile("Preserving active timer ending at: \(timer.endTime)")
        } else {
            treatmentTimer = nil
        }
        
        saveCachedData()
        saveTimerState()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func checkAndResetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if lastResetDate == nil || !Calendar.current.isDate(lastResetDate!, inSameDayAs: today) {
            resetDaily()
        }
    }
    
    func currentCycleId() -> UUID? {
        let today = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        
        // First check if today is within any cycle's date range
        for cycle in cycles {
            let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
            let cycleEndDay = calendar.startOfDay(for: cycle.foodChallengeDate)
            
            if todayStart >= cycleStartDay && todayStart <= cycleEndDay {
                return cycle.id
            }
        }
        
        // If we're between cycles, use the most recent cycle that has started
        return cycles.filter {
            calendar.startOfDay(for: $0.startDate) <= todayStart
        }.max(by: {
            $0.startDate < $1.startDate
        })?.id ?? cycles.last?.id
    }
    
    func verifyFirebaseState() {
        guard let dbRef = dbRef else { return }
        dbRef.child("cycles").observeSingleEvent(of: .value) { snapshot in
            if let value = snapshot.value as? [String: [String: Any]] {
                // print("Final Firebase cycles state: \(value)")
                self.logToFile("Final Firebase cycles state: \(value)")
            } else {
                // print("Final Firebase cycles state is empty or missing")
                self.logToFile("Final Firebase cycles state is empty or missing")
            }
        }
    }
    
    func rescheduleDailyReminders() {
        guard let user = currentUser, let roomId = currentRoomId else { return }
        
        // Cancel all existing reminders for this user/room
        let userId = user.id.uuidString
        var identifiersToCancel: [String] = []
        for category in Category.allCases {
            let identifier = "reminder_\(userId)_\(category.rawValue)_\(roomId)"
            identifiersToCancel.append(identifier)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        
        // Schedule new reminders for enabled categories
        for category in Category.allCases {
            if let roomSettings = user.roomSettings?[roomId],
               roomSettings.remindersEnabled[category] == true,
               let time = roomSettings.reminderTimes[category] {
                scheduleReminderForCategory(category: category, time: time, roomId: roomId, userId: userId)
            }
        }
        
        // Schedule next daily reschedule
        DispatchQueue.main.asyncAfter(deadline: .now() + 24 * 3600) {
            self.rescheduleDailyReminders()
        }
    }

    private func scheduleReminderForCategory(category: Category, time: Date, roomId: String, userId: String) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        
        // Get the room name (patient name) for the notification
        let participantName = cycles.last?.patientName ?? "TIPs Program"
        
        let content = UNMutableNotificationContent()
        content.title = "\(participantName): Dose reminder for \(category.rawValue)"
        content.body = "Have you logged all items in \(category.rawValue) for \(participantName)?"
        content.sound = .default
        content.categoryIdentifier = "REMINDER_CATEGORY"
        content.userInfo = ["roomId": roomId, "category": category.rawValue]
       content.badge = 0
        
        var triggerComponents = DateComponents()
        triggerComponents.hour = hour
        triggerComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        let identifier = "reminder_\(userId)_\(category.rawValue)_\(roomId)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reminder for \(category.rawValue): \(error.localizedDescription)")
            } else {
                let timeString = String(format: "%02d:%02d", hour, minute)
                print("Scheduled repeating reminder for \(category.rawValue) at \(timeString) local time (identifier: \(identifier))")
            }
        }
    }
    func refreshSubscriptionStatus() {
        // Force refresh from RevenueCat
        StoreManager.shared.checkSubscriptionStatus()
    }
    // MARK: - Transfer Ownership Methods
    
    @Published var transferRequests: [TransferRequest] = []
    
    // MARK: - Transfer Ownership Methods

    // Helper method to validate a user's subscription and room capacity
    private func validateUserCapacity(userId: UUID, roomId: String, completion: @escaping (Bool, String?) -> Void) {
        let dbRef = Database.database().reference()
        logToFile("Validating capacity for user: \(userId.uuidString), room: \(roomId)")
        
        dbRef.child("users").child(userId.uuidString).observeSingleEvent(of: .value) { snapshot in
            guard let userData = snapshot.value as? [String: Any],
                  let user = User(dictionary: userData) else {
                self.logToFile("ERROR: Could not load user data for \(userId.uuidString)")
                completion(false, "Could not load user data")
                return
            }
            
            let roomCount = user.ownedRooms?.count ?? 0
            let roomLimit = user.roomLimit
            
            self.logToFile("User \(user.name) capacity - rooms: \(roomCount)/\(roomLimit), plan: \(user.subscriptionPlan ?? "none")")
            
            if roomLimit == 0 {
                self.logToFile("Validation failed: User has no subscription (roomLimit = 0)")
                completion(false, "UPGRADE_NEEDED")
            } else if roomCount >= roomLimit {
                self.logToFile("Validation failed: User has reached room limit (\(roomCount)/\(roomLimit))")
                completion(false, "User has reached their room limit of \(roomLimit). Please upgrade their subscription.")
            } else {
                self.logToFile("Validation passed: User has capacity (\(roomCount)/\(roomLimit))")
                completion(true, nil)
            }
        }
    }

    // Unified method to accept a transfer request (handles both Owner to User and User to Owner)
    func acceptTransferRequest(requestId: UUID, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser else {
            logToFile("ERROR: No current user when accepting request \(requestId.uuidString)")
            completion(false, "No current user")
            return
        }
        
        let dbRef = Database.database().reference()
        logToFile("Accepting transfer request \(requestId.uuidString) for user: \(currentUser.id.uuidString)")
        
        // Fetch the transfer request
        dbRef.child("transferRequests").child(requestId.uuidString).observeSingleEvent(of: .value) { snapshot in
            guard let requestData = snapshot.value as? [String: Any],
                  let request = TransferRequest(dictionary: requestData) else {
                self.logToFile("ERROR: Transfer request \(requestId.uuidString) not found")
                completion(false, "Transfer request not found")
                return
            }
            
            guard request.canBeAccepted else {
                self.logToFile("ERROR: Request \(requestId.uuidString) cannot be accepted - status: \(request.status.rawValue), expired: \(request.isExpired)")
                completion(false, "This transfer request has expired or is no longer valid")
                return
            }
            
            // Verify the new owner (explicitly stored in newOwnerId)
            let newOwnerId = request.newOwnerId
            self.logToFile("New owner ID: \(newOwnerId.uuidString)")
            
            // Validate the new owner's capacity
            self.validateUserCapacity(userId: newOwnerId, roomId: request.roomId) { isValid, error in
                if !isValid {
                    self.logToFile("Capacity validation failed for new owner \(newOwnerId.uuidString): \(error ?? "unknown")")
                    if error == "UPGRADE_NEEDED" {
                        dbRef.child("transferRequests").child(requestId.uuidString).child("status").setValue("accepted_pending_subscription") { error, _ in
                            if let error = error {
                                self.logToFile("ERROR: Failed to set accepted_pending_subscription: \(error.localizedDescription)")
                                completion(false, error.localizedDescription)
                            } else {
                                self.removeFromPendingRequests(requestId: requestId.uuidString)
                                completion(false, "UPGRADE_NEEDED")
                            }
                        }
                    } else {
                        completion(false, error ?? "Capacity validation failed")
                    }
                    return
                }
                
                // Execute the transfer
                self.executeRoomTransfer(request: request) { success, error in
                    self.logToFile("Transfer execution result - success: \(success), error: \(error ?? "none")")
                    completion(success, error)
                }
            }
        }
    }

    // Updated method to send a transfer request (Owner to User flow)
    func sendOwnerTransferRequest(roomId: String, roomName: String, toUserId: UUID, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser else {
            logToFile("ERROR: No current user for sendOwnerTransferRequest")
            completion(false, "No current user")
            return
        }
        
        guard currentUser.ownedRooms?.contains(roomId) == true else {
            logToFile("ERROR: User \(currentUser.id.uuidString) doesn't own room \(roomId)")
            completion(false, "You don't own this room")
            return
        }
        
        let dbRef = Database.database().reference()
        logToFile("Sending owner transfer request - room: \(roomId), from: \(currentUser.id.uuidString) to: \(toUserId.uuidString)")
        
        // Cancel any existing pending requests for this room from this owner
        dbRef.child("transferRequests").queryOrdered(byChild: "initiatorUserId").queryEqual(toValue: currentUser.id.uuidString)
            .observeSingleEvent(of: .value) { snapshot in
                var requestsToCancel: [String] = []
                
                if let allRequests = snapshot.value as? [String: [String: Any]] {
                    for (requestId, requestData) in allRequests {
                        if let requestRoomId = requestData["roomId"] as? String,
                           let requestRecipientId = requestData["recipientUserId"] as? String,
                           let status = requestData["status"] as? String,
                           requestRoomId == roomId &&
                           requestRecipientId == toUserId.uuidString &&
                           status == "pending" {
                            requestsToCancel.append(requestId)
                            self.logToFile("Found duplicate request to cancel: \(requestId)")
                        }
                    }
                }
                
                // Cancel old requests
                let cancelGroup = DispatchGroup()
                for requestId in requestsToCancel {
                    cancelGroup.enter()
                    dbRef.child("transferRequests").child(requestId).child("status").setValue("cancelled") { _, _ in
                        self.logToFile("Cancelled old request: \(requestId)")
                        cancelGroup.leave()
                    }
                }
                
                cancelGroup.notify(queue: .global()) {
                    // Create new transfer request (Owner to User)
                    let transferRequest = TransferRequest(
                        initiatorUserId: currentUser.id, // Owner
                        initiatorUserName: currentUser.name,
                        recipientUserId: toUserId, // Invited user
                        newOwnerId: toUserId, // Invited user will be new owner
                        roomId: roomId,
                        roomName: roomName
                    )
                    
                    self.logToFile("Creating new transfer request: \(transferRequest.id.uuidString)")
                    
                    // Save to Firebase
                    dbRef.child("transferRequests").child(transferRequest.id.uuidString).setValue(transferRequest.toDictionary()) { error, _ in
                        if let error = error {
                            self.logToFile("ERROR: Failed to save transfer request: \(error.localizedDescription)")
                            completion(false, error.localizedDescription)
                            return
                        }
                        
                        // Add to recipient's pending requests
                        dbRef.child("users").child(toUserId.uuidString).child("pendingTransferRequests").observeSingleEvent(of: .value) { userSnapshot in
                            var pendingRequests = userSnapshot.value as? [String] ?? []
                            pendingRequests = pendingRequests.filter { !requestsToCancel.contains($0) }
                            
                            if !pendingRequests.contains(transferRequest.id.uuidString) {
                                pendingRequests.append(transferRequest.id.uuidString)
                            }
                            
                            dbRef.child("users").child(toUserId.uuidString).child("pendingTransferRequests").setValue(pendingRequests) { error, _ in
                                if let error = error {
                                    self.logToFile("ERROR: Failed to update pending requests: \(error.localizedDescription)")
                                    completion(false, error.localizedDescription)
                                } else {
                                    self.loadSentTransferRequests()
                                    completion(true, nil)
                                }
                            }
                        }
                    }
                }
            }
    }

    // Updated method to request room ownership (User to Owner flow)
    func createOwnershipRequest(roomId: String, ownerId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser else {
            logToFile("ERROR: No current user for createOwnershipRequest")
            completion(false, "No current user")
            return
        }

        // Validate current user's capacity
        validateUserCapacity(userId: currentUser.id, roomId: roomId) { isValid, error in
            if !isValid {
                self.logToFile("Capacity validation failed for requester \(currentUser.id.uuidString): \(error ?? "unknown")")
                completion(false, error ?? "You don't have capacity to request ownership")
                return
            }

            let dbRef = Database.database().reference()

            // Validate initiator is a room member
            dbRef.child("rooms").child(roomId).child("users").child(currentUser.id.uuidString).observeSingleEvent(of: .value) { snapshot in
                guard snapshot.exists() else {
                    self.logToFile("ERROR: User \(currentUser.id.uuidString) is not a member of room \(roomId)")
                    completion(false, "You are not a member of this room")
                    return
                }

                // Validate recipient is the room owner
                dbRef.child("rooms").child(roomId).child("ownerId").observeSingleEvent(of: .value) { ownerSnapshot in
                    guard let roomOwnerId = ownerSnapshot.value as? String,
                          roomOwnerId == ownerId else {
                        self.logToFile("ERROR: Recipient \(ownerId) is not the owner of room \(roomId)")
                        completion(false, "Recipient is not the room owner")
                        return
                    }

                    // Get room name
                    dbRef.child("rooms").child(roomId).observeSingleEvent(of: .value) { snapshot in
                        var roomName = "Unknown Room"
                        if let roomData = snapshot.value as? [String: Any],
                           let cycles = roomData["cycles"] as? [String: [String: Any]] {
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
                                roomName = "\(patientName)'s Program"
                            }
                        }

                        // Clean up existing requests
                        dbRef.child("transferRequests").observeSingleEvent(of: .value) { snapshot in
                            var requestsToCancel: [String] = []

                            if let allRequests = snapshot.value as? [String: [String: Any]] {
                                for (requestId, requestData) in allRequests {
                                    if let requestRoomId = requestData["roomId"] as? String,
                                       let requestInitiatorId = requestData["initiatorUserId"] as? String,
                                       let status = requestData["status"] as? String,
                                       requestRoomId == roomId &&
                                       requestInitiatorId == currentUser.id.uuidString &&
                                       status == "pending" {
                                        requestsToCancel.append(requestId)
                                    }
                                }
                            }

                            let cancelGroup = DispatchGroup()
                            for requestId in requestsToCancel {
                                cancelGroup.enter()
                                dbRef.child("transferRequests").child(requestId).child("status").setValue("cancelled") { _, _ in
                                    self.logToFile("Cancelled existing request: \(requestId)")
                                    cancelGroup.leave()
                                }
                            }

                            if !requestsToCancel.isEmpty {
                                cancelGroup.enter()
                                dbRef.child("users").child(ownerId).child("pendingTransferRequests").observeSingleEvent(of: .value) { ownerSnapshot in
                                    var pendingRequests = ownerSnapshot.value as? [String] ?? []
                                    pendingRequests = pendingRequests.filter { !requestsToCancel.contains($0) }
                                    dbRef.child("users").child(ownerId).child("pendingTransferRequests").setValue(pendingRequests.isEmpty ? nil : pendingRequests) { _, _ in
                                        cancelGroup.leave()
                                    }
                                }
                            }

                            cancelGroup.notify(queue: .global()) {
                                // Create new transfer request
                                let transferRequest = TransferRequest(
                                    initiatorUserId: currentUser.id, // Room member requesting ownership
                                    initiatorUserName: currentUser.name,
                                    recipientUserId: UUID(uuidString: ownerId) ?? UUID(), // Current owner
                                    newOwnerId: currentUser.id, // Initiator becomes new owner
                                    roomId: roomId,
                                    roomName: roomName
                                )

                                self.logToFile("Creating new ownership request: \(transferRequest.id.uuidString)")

                                // Save to Firebase
                                dbRef.child("transferRequests").child(transferRequest.id.uuidString).setValue(transferRequest.toDictionary()) { error, _ in
                                    if let error = error {
                                        self.logToFile("ERROR: Failed to save ownership request: \(error.localizedDescription)")
                                        completion(false, error.localizedDescription)
                                        return
                                    }

                                    // Add to recipient's pending requests
                                    dbRef.child("users").child(ownerId).child("pendingTransferRequests").observeSingleEvent(of: .value) { ownerSnapshot in
                                        var pendingRequests = ownerSnapshot.value as? [String] ?? []
                                        if !pendingRequests.contains(transferRequest.id.uuidString) {
                                            pendingRequests.append(transferRequest.id.uuidString)
                                        }

                                        dbRef.child("users").child(ownerId).child("pendingTransferRequests").setValue(pendingRequests) { error, _ in
                                            if let error = error {
                                                self.logToFile("ERROR: Failed to update recipient's pending requests: \(error.localizedDescription)")
                                                completion(false, error.localizedDescription)
                                            } else {
                                                NotificationCenter.default.post(
                                                    name: Notification.Name("TransferRequestReceived"),
                                                    object: nil,
                                                    userInfo: ["ownerId": ownerId]
                                                )
                                                completion(true, nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func executeRoomTransfer(request: TransferRequest, completion: @escaping (Bool, String?) -> Void) {
        let dbRef = Database.database().reference()
        logToFile("Executing transfer for request: \(request.id.uuidString), room: \(request.roomId), initiator: \(request.initiatorUserId.uuidString), new owner: \(request.newOwnerId.uuidString)")

        // Validate room exists
        dbRef.child("rooms").child(request.roomId).observeSingleEvent(of: .value) { snapshot in
            guard snapshot.exists() else {
                self.logToFile("ERROR: Room \(request.roomId) does not exist")
                completion(false, "Room does not exist")
                return
            }

            // Get all users with the room in ownedRooms
            dbRef.child("users").observeSingleEvent(of: .value) { usersSnapshot in
                guard let usersData = usersSnapshot.value as? [String: [String: Any]] else {
                    self.logToFile("ERROR: Could not fetch users")
                    completion(false, "Could not fetch users")
                    return
                }

                var updateData: [String: Any] = [
                    "rooms/\(request.roomId)/ownerId": request.newOwnerId.uuidString,
                    "transferRequests/\(request.id.uuidString)/status": "accepted",
                    "users/\(request.newOwnerId.uuidString)/ownedRooms": [request.roomId], // Set new owner's ownedRooms
                    "users/\(request.recipientUserId.uuidString)/pendingTransferRequests": NSNull() // Clear pending requests
                ]

                // Clear ownedRooms and grace period for all other users who claim ownership
                for (userId, userData) in usersData {
                    if userId != request.newOwnerId.uuidString,
                       let ownedRooms = userData["ownedRooms"] as? [String],
                       ownedRooms.contains(request.roomId) {
                        updateData["users/\(userId)/ownedRooms"] = NSNull()
                        
                        // Clear grace period status for users who no longer own rooms
                        updateData["users/\(userId)/isInGracePeriod"] = false
                        updateData["users/\(userId)/subscriptionGracePeriodEnd"] = NSNull()
                        
                        self.logToFile("Clearing ownedRooms and grace period for user \(userId) who had room \(request.roomId)")
                    }
                }

                // Run multi-location update
                dbRef.updateChildValues(updateData) { error, _ in
                    if let error = error {
                        self.logToFile("ERROR: Transaction failed: \(error.localizedDescription)")
                        completion(false, "Transfer failed: \(error.localizedDescription)")
                        return
                    }

                    self.logToFile("Transaction successful: Room \(request.roomId) transferred to \(request.newOwnerId.uuidString)")

                    // Verify the update
                    dbRef.child("users").child(request.initiatorUserId.uuidString).child("ownedRooms").observeSingleEvent(of: .value) { initiatorSnapshot in
                        let initiatorOwnedRooms = initiatorSnapshot.value as? [String] ?? []
                        self.logToFile("Post-transfer: Initiator \(request.initiatorUserId.uuidString) ownedRooms: \(initiatorOwnedRooms)")

                        dbRef.child("users").child(request.newOwnerId.uuidString).child("ownedRooms").observeSingleEvent(of: .value) { newOwnerSnapshot in
                            let newOwnedRooms = newOwnerSnapshot.value as? [String] ?? []
                            self.logToFile("Post-transfer: New owner \(request.newOwnerId.uuidString) ownedRooms: \(newOwnedRooms)")

                            // Refresh user data and grace period status
                            if request.newOwnerId == self.currentUser?.id {
                                self.forceRefreshCurrentUser()
                            }
                            self.forceRefreshUserData(userId: request.newOwnerId.uuidString) {}
                            self.forceRefreshUserData(userId: request.initiatorUserId.uuidString) {}

                            // Force refresh grace period status for current user if they were involved in the transfer
                            if self.currentUser?.id.uuidString == request.initiatorUserId.uuidString ||
                               self.currentUser?.id.uuidString == request.newOwnerId.uuidString {
                                DispatchQueue.main.async {
                                    // Clear local grace period status immediately
                                    self.isInGracePeriod = false
                                    self.subscriptionGracePeriodEnd = nil
                                    
                                    // Then refresh from Firebase
                                    self.forceRefreshCurrentUser {
                                        // Force UI update
                                        self.objectWillChange.send()
                                    }
                                }
                            }

                            NotificationCenter.default.post(
                                name: Notification.Name("OwnershipChanged"),
                                object: nil,
                                userInfo: [
                                    "roomId": request.roomId,
                                    "newOwnerId": request.newOwnerId.uuidString,
                                    "oldOwnerId": request.initiatorUserId.uuidString
                                ]
                            )

                            // Force refresh grace period status for all involved users
                            DispatchQueue.main.async {
                                // Clear grace period for users who no longer own any rooms
                                for (userId, userData) in usersData {
                                    if userId == self.currentUser?.id.uuidString {
                                        let userOwnedRooms = userData["ownedRooms"] as? [String] ?? []
                                        let stillOwnsRooms = userOwnedRooms.contains { $0 != request.roomId }
                                        
                                        if !stillOwnsRooms {
                                            self.isInGracePeriod = false
                                            self.subscriptionGracePeriodEnd = nil
                                            self.objectWillChange.send()
                                            self.logToFile("Cleared local grace period for current user after transfer")
                                        }
                                    }
                                }
                                
                                // Send notification to refresh grace period UI
                                NotificationCenter.default.post(
                                    name: Notification.Name("GracePeriodStatusChanged"),
                                    object: nil
                                )
                            }

                            completion(true, nil)
                        }
                    }
                }
            }
        }
    }

    // Update loadSentTransferRequests to use new schema
    func loadSentTransferRequests() {
        guard let currentUser = currentUser else {
            sentTransferRequests = []
            return
        }
        
        let dbRef = Database.database().reference()
        dbRef.child("transferRequests").queryOrdered(byChild: "initiatorUserId").queryEqual(toValue: currentUser.id.uuidString)
            .observeSingleEvent(of: .value) { snapshot in
                var loadedRequests: [TransferRequest] = []
                
                if let requests = snapshot.value as? [String: [String: Any]] {
                    for (_, requestData) in requests {
                        if let request = TransferRequest(dictionary: requestData) {
                            if !request.isExpired || ["accepted", "declined"].contains(request.status.rawValue) {
                                loadedRequests.append(request)
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.sentTransferRequests = loadedRequests.sorted { $0.requestDate > $1.requestDate }
                    self.objectWillChange.send()
                }
            }
    }

    // Update cancelTransferRequest to use new schema
    func cancelTransferRequest(requestId: UUID, completion: @escaping (Bool, String?) -> Void) {
        let dbRef = Database.database().reference()
        logToFile("Cancelling transfer request: \(requestId.uuidString)")
        
        dbRef.child("transferRequests").child(requestId.uuidString).child("status").setValue("cancelled") { error, _ in
            if let error = error {
                self.logToFile("ERROR: Failed to cancel request: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                self.loadSentTransferRequests()
                completion(true, nil)
            }
        }
    }
    

    
    func cleanupExpiredTransferRequests() {
        guard let currentUser = currentUser else { return }
        
        let dbRef = Database.database().reference()
        
        // Clean up expired requests from the main collection
        dbRef.child("transferRequests").observeSingleEvent(of: .value) { snapshot in
            guard let allRequests = snapshot.value as? [String: [String: Any]] else { return }
            
            let now = Date()
            var expiredRequestIds: [String] = []
            
            for (requestId, requestData) in allRequests {
                if let expiresAtStr = requestData["expiresAt"] as? String,
                   let expiresAt = ISO8601DateFormatter().date(from: expiresAtStr),
                   now > expiresAt {
                    expiredRequestIds.append(requestId)
                }
            }
            
            // Remove expired requests
            for requestId in expiredRequestIds {
                dbRef.child("transferRequests").child(requestId).removeValue()
            }
            
            // Clean up user's pending requests array
            if let pendingRequests = currentUser.pendingTransferRequests {
                let validRequests = pendingRequests.filter { !expiredRequestIds.contains($0) }
                if validRequests.count != pendingRequests.count {
                    dbRef.child("users").child(currentUser.id.uuidString).child("pendingTransferRequests").setValue(validRequests.isEmpty ? nil : validRequests)
                }
            }
        }
    }
    
    func loadTransferRequests() {
        guard let currentUser = currentUser else {
            transferRequests = []
            return
        }
        
        // First clean up any dangling references
        cleanupDanglingTransferRequests {
            // Then load the actual requests
            self.performLoadTransferRequests()
        }
    }

    // NEW: Split the actual loading logic into a separate method
    private func performLoadTransferRequests() {
        guard let currentUser = currentUser else {
            transferRequests = []
            return
        }
        
        // First clean up expired requests
        cleanupExpiredTransferRequests()
        
        // Then load current valid requests
        guard let pendingRequestIds = currentUser.pendingTransferRequests else {
            transferRequests = []
            return
        }
        
        let dbRef = Database.database().reference()
        var loadedRequests: [TransferRequest] = []
        let group = DispatchGroup()
        
        for requestId in pendingRequestIds {
            group.enter()
            dbRef.child("transferRequests").child(requestId).observeSingleEvent(of: .value) { snapshot, _ in
                defer { group.leave() }
                
                if let requestData = snapshot.value as? [String: Any],
                   let request = TransferRequest(dictionary: requestData) {
                    if request.canBeAccepted {
                        loadedRequests.append(request)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            self.transferRequests = loadedRequests.sorted { $0.requestDate > $1.requestDate }
            self.objectWillChange.send()
        }
    }
    

    func debugDeclineTransferRequest(requestId: UUID, reason: String) {
        print("🚨 DEBUG DECLINE: Request \(requestId) being declined. Reason: \(reason)")
        print("🚨 DEBUG DECLINE: Call stack: \(Thread.callStackSymbols)")
    }
    
    // NEW: Clean up dangling transfer request references
    func cleanupDanglingTransferRequests(completion: @escaping () -> Void = {}) {
        guard let currentUser = currentUser, !isCleaningUp else {
            completion()
            return
        }
        
        isCleaningUp = true
        
        let dbRef = Database.database().reference()
        let userId = currentUser.id.uuidString
        
        // Get user's pending requests
        dbRef.child("users").child(userId).child("pendingTransferRequests").observeSingleEvent(of: .value) { snapshot, _ in
            guard let pendingRequestIds = snapshot.value as? [String], !pendingRequestIds.isEmpty else {
                completion()
                return
            }
            
            print("DEBUG: Found \(pendingRequestIds.count) pending request IDs in user object")
            
            let group = DispatchGroup()
            var validRequestIds: [String] = []
            
            // Check each request ID to see if it actually exists
            for requestId in pendingRequestIds {
                group.enter()
                dbRef.child("transferRequests").child(requestId).observeSingleEvent(of: .value) { requestSnapshot, _ in
                    defer { group.leave() }
                    
                    if requestSnapshot.exists() {
                        validRequestIds.append(requestId)
                        print("DEBUG: Request \(requestId) exists - keeping")
                    } else {
                        print("DEBUG: Request \(requestId) not found - removing reference")
                    }
                }
            }
            
            group.notify(queue: .main) {
                // Update user's pending requests with only valid IDs
                if validRequestIds.count != pendingRequestIds.count {
                    print("DEBUG: Cleaning up user's pending requests. Before: \(pendingRequestIds.count), After: \(validRequestIds.count)")
                    
                    dbRef.child("users").child(userId).child("pendingTransferRequests").setValue(validRequestIds.isEmpty ? nil : validRequestIds) { error, _ in
                        if let error = error {
                            print("DEBUG: Error cleaning up pending requests: \(error.localizedDescription)")
                        } else {
                            print("DEBUG: Successfully cleaned up pending requests")
                            
                            // Update local user object
                            DispatchQueue.main.async {
                                var updatedUser = currentUser
                                updatedUser.pendingTransferRequests = validRequestIds.isEmpty ? nil : validRequestIds
                                self.currentUser = updatedUser
                                self.objectWillChange.send()
                            }
                        }
                        
                        self.isCleaningUp = false  // Reset flag
                        completion()
                    }
                } else {
                    print("DEBUG: No cleanup needed - all references are valid")
                    self.isCleaningUp = false  // Reset flag
                    completion()
                }
            }
        }
    }
    
    func declineTransferRequest(requestId: UUID, completion: @escaping (Bool, String?) -> Void) {
        debugStatusChange(requestId: requestId.uuidString, newStatus: "declined", location: "declineTransferRequest method")
        
        let dbRef = Database.database().reference()
        
        // Update request status to declined
        dbRef.child("transferRequests").child(requestId.uuidString).child("status").setValue("declined") { error, _ in
            if let error = error {
                print("🚨 DEBUG: Error declining request: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("🚨 DEBUG: Successfully declined request \(requestId)")
                // Remove from user's pending requests
                self.removeFromPendingRequests(requestId: requestId.uuidString)
                completion(true, nil)
            }
        }
    }
    

    
    private func removeFromPendingRequests(requestId: String) {
        guard let currentUser = currentUser else { return }
        
        let dbRef = Database.database().reference()
        dbRef.child("users").child(currentUser.id.uuidString).child("pendingTransferRequests").observeSingleEvent(of: .value) { snapshot in
            if var pendingRequests = snapshot.value as? [String] {
                pendingRequests.removeAll { $0 == requestId }
                dbRef.child("users").child(currentUser.id.uuidString).child("pendingTransferRequests").setValue(pendingRequests.isEmpty ? nil : pendingRequests)
            }
        }
        
        // Remove from local array
        DispatchQueue.main.async {
            self.transferRequests.removeAll { $0.id.uuidString == requestId }
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Room Owner Grace Period Detection
    func checkRoomOwnerGracePeriod(roomId: String) {
        let dbRef = Database.database().reference()
        
        // First get the room's owner ID
        dbRef.child("rooms").child(roomId).child("ownerId").observeSingleEvent(of: .value) { snapshot in
            guard let ownerId = snapshot.value as? String else {
                // Fallback: check room users for admin
                self.checkRoomOwnerFromUsers(roomId: roomId)
                return
            }
            
            // Check if this user is the owner
            if ownerId == self.currentUser?.id.uuidString {
                // Current user is owner, don't show invited user alert
                DispatchQueue.main.async {
                    self.roomOwnerInGracePeriod = false
                    self.roomOwnerGracePeriodEnd = nil
                }
                return
            }
            
            // Check owner's grace period status
            dbRef.child("users").child(ownerId).observeSingleEvent(of: .value) { userSnapshot in
                if let userData = userSnapshot.value as? [String: Any] {
                    let isInGracePeriod = userData["isInGracePeriod"] as? Bool ?? false
                    var gracePeriodEnd: Date? = nil
                    
                    if let gracePeriodEndStr = userData["subscriptionGracePeriodEnd"] as? String {
                        gracePeriodEnd = ISO8601DateFormatter().date(from: gracePeriodEndStr)
                    }
                    
                    DispatchQueue.main.async {
                        self.roomOwnerInGracePeriod = isInGracePeriod && gracePeriodEnd != nil && gracePeriodEnd! > Date()
                        self.roomOwnerGracePeriodEnd = gracePeriodEnd
                        // print("Room owner grace period status: \(self.roomOwnerInGracePeriod), end: \(String(describing: gracePeriodEnd))")
                    }
                }
            }
        }
    }
    
    private func checkRoomOwnerFromUsers(roomId: String) {
        let dbRef = Database.database().reference()
        
        // Get all users in the room and find the admin/owner
        dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { snapshot in
            guard let usersData = snapshot.value as? [String: Any] else { return }
            
            // Look for admin users
            for (userId, userData) in usersData {
                if let userDict = userData as? [String: Any],
                   let isAdmin = userDict["isAdmin"] as? Bool,
                   isAdmin == true {
                    
                    // Check this admin's grace period status
                    dbRef.child("users").child(userId).observeSingleEvent(of: .value) { userSnapshot in
                        if let fullUserData = userSnapshot.value as? [String: Any] {
                            let isInGracePeriod = fullUserData["isInGracePeriod"] as? Bool ?? false
                            var gracePeriodEnd: Date? = nil
                            
                            if let gracePeriodEndStr = fullUserData["subscriptionGracePeriodEnd"] as? String {
                                gracePeriodEnd = ISO8601DateFormatter().date(from: gracePeriodEndStr)
                            }
                            
                            // Only update if current user is not the owner
                            if userId != self.currentUser?.id.uuidString {
                                DispatchQueue.main.async {
                                    self.roomOwnerInGracePeriod = isInGracePeriod && gracePeriodEnd != nil && gracePeriodEnd! > Date()
                                    self.roomOwnerGracePeriodEnd = gracePeriodEnd
                                }
                            }
                            return // Found the owner, stop checking
                        }
                    }
                    return
                }
            }
        }
    }
    
    func checkPendingOwnershipRequests() {
        guard let currentUser = currentUser else {
            DispatchQueue.main.async {
                self.hasPendingOwnershipRequests = false
            }
            return
        }
        
        // Check pending transfer requests where current user is the recipient (toUserId)
        let dbRef = Database.database().reference()
        
        dbRef.child("transferRequests").queryOrdered(byChild: "fromUserId").queryEqual(toValue: currentUser.id.uuidString)
            .observeSingleEvent(of: .value) { snapshot in
                
                var hasValidRequests = false
                
                if let requests = snapshot.value as? [String: [String: Any]] {
                    for (_, requestData) in requests {
                        if let status = requestData["status"] as? String,
                           status == "pending",
                           let expiresAtStr = requestData["expiresAt"] as? String,
                           let expiresAt = ISO8601DateFormatter().date(from: expiresAtStr),
                           expiresAt > Date() {
                            hasValidRequests = true
                            break
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.hasPendingOwnershipRequests = hasValidRequests
                    // print("DEBUG: Has pending ownership requests: \(hasValidRequests)")
                }
            }
    }
    
    func requestRoomOwnership(roomId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser else {
            completion(false, "No current user")
            return
        }
        
        // Check if user has room capacity
        let currentRoomCount = currentUser.ownedRooms?.count ?? 0
        let roomLimit = currentUser.roomLimit
        
        if roomLimit == 0 {
            completion(false, "UPGRADE_NEEDED")
            return
        }
        
        if currentRoomCount >= roomLimit {
            completion(false, "You've reached your room limit of \(roomLimit). Upgrade your subscription to request ownership.")
            return
        }
        
        // Find room owner
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("ownerId").observeSingleEvent(of: .value) { snapshot in
            var ownerId: String?
            
            if let ownerIdFromSnapshot = snapshot.value as? String {
                ownerId = ownerIdFromSnapshot
            } else {
                // Fallback: find admin in room users
                dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { usersSnapshot in
                    if let usersData = usersSnapshot.value as? [String: Any] {
                        for (userId, userData) in usersData {
                            if let userDict = userData as? [String: Any],
                               let isAdmin = userDict["isAdmin"] as? Bool,
                               isAdmin == true {
                                ownerId = userId
                                break
                            }
                        }
                    }
                    
                    if let finalOwnerId = ownerId {
                        self.createOwnershipRequest(roomId: roomId, ownerId: finalOwnerId, completion: completion)
                    } else {
                        completion(false, "Could not find room owner")
                    }
                }
                return
            }
            
            if let finalOwnerId = ownerId {
                self.createOwnershipRequest(roomId: roomId, ownerId: finalOwnerId, completion: completion)
            } else {
                completion(false, "Could not find room owner")
            }
        }
    }
    

    

    private func forceRefreshUserData(userId: String, completion: @escaping () -> Void) {
        let dbRef = Database.database().reference()
        
        dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
            if let userData = snapshot.value as? [String: Any] {
                var userDict = userData
                userDict["id"] = userId
                
                if let user = User(dictionary: userDict) {
                    DispatchQueue.main.async {
                        // Update in users array if this user exists there
                        if let index = self.users.firstIndex(where: { $0.id.uuidString == userId }) {
                            self.users[index] = user
                            print("DEBUG: Force refreshed user data for: \(user.name)")
                        }
                        
                        // If it's the current user, update current user too
                        if userId == self.currentUser?.id.uuidString {
                            self.currentUser = user
                        }
                        
                        self.objectWillChange.send()
                        completion()
                    }
                } else {
                    completion()
                }
            } else {
                completion()
            }
        }
    }
    // MARK: - Live Activity Methods
    @available(iOS 16.1, *)
    private func startLiveActivity(roomId: String, roomName: String, endTime: Date, duration: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }
        
        let attributes = TreatmentTimerAttributes(roomName: roomName, roomId: roomId)
        let contentState = TreatmentTimerAttributes.ContentState(
            endTime: endTime,
            isActive: true,
            totalDuration: duration
        )
        
        do {
            let activity = try Activity<TreatmentTimerAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            print("Live Activity started: \(activity.id)")
            logToFile("Live Activity started: \(activity.id)")
            
            // NEW: Save Live Activity state to Firebase so all users can see it
            saveLiveActivityStateToFirebase(roomId: roomId, roomName: roomName, endTime: endTime, duration: duration, isActive: true)
            
        } catch {
            print("Error starting Live Activity: \(error)")
            logToFile("Error starting Live Activity: \(error)")
        }
    }
    
    @available(iOS 16.1, *)
    private func updateLiveActivity(roomId: String, endTime: Date, isActive: Bool, totalDuration: TimeInterval) {
        let activities = Activity<TreatmentTimerAttributes>.activities
        
        for activity in activities {
            if activity.attributes.roomId == roomId && activity.activityState == .active {
                let contentState = TreatmentTimerAttributes.ContentState(
                    endTime: endTime,
                    isActive: isActive,
                    totalDuration: totalDuration
                )
                
                Task {
                    await activity.update(using: contentState)
                }
                break
            }
        }
    }
    @available(iOS 16.1, *)
    func endLiveActivity(roomId: String) {
        let activities = Activity<TreatmentTimerAttributes>.activities
        
        for activity in activities {
            if activity.attributes.roomId == roomId && activity.activityState == .active {
                let contentState = TreatmentTimerAttributes.ContentState(
                    endTime: Date(),
                    isActive: false,
                    totalDuration: 900.0
                )
                
                Task {
                    await activity.end(using: contentState, dismissalPolicy: .immediate)
                }
                print("Live Activity ended for room: \(roomId)")
                logToFile("Live Activity ended for room: \(roomId)")
                break
            }
        }
        
        // NEW: Clear Live Activity state from Firebase
        clearLiveActivityStateFromFirebase(roomId: roomId)
    }
    @available(iOS 16.1, *)
    func updateExpiredLiveActivity(roomId: String, endTime: Date, totalDuration: TimeInterval) {
        let activities = Activity<TreatmentTimerAttributes>.activities
        
        for activity in activities {
            if activity.attributes.roomId == roomId && activity.activityState == .active {
                // FIXED: Set endTime to current time to prevent counting up
                let expiredContentState = TreatmentTimerAttributes.ContentState(
                    endTime: Date(), // Use current time instead of original endTime
                    isActive: false,  // Mark as inactive
                    totalDuration: totalDuration
                )
                
                Task {
                    await activity.update(using: expiredContentState)
                }
                print("Updated Live Activity to show expired state for room: \(roomId)")
                logToFile("Updated Live Activity to show expired state for room: \(roomId)")
                break
            }
        }
    }
    
    @available(iOS 16.1, *)
    func updateLiveActivityProgress(roomId: String, endTime: Date, isActive: Bool, totalDuration: TimeInterval) {
        let activities = Activity<TreatmentTimerAttributes>.activities
        
        for activity in activities {
            if activity.attributes.roomId == roomId && activity.activityState == .active {
                let contentState = TreatmentTimerAttributes.ContentState(
                    endTime: endTime,
                    isActive: isActive,
                    totalDuration: totalDuration
                )
                
                Task {
                    await activity.update(using: contentState)
                }
                // Don't log every second to avoid spam
                break
            }
        }
    }
    // MARK: - Live Activity Firebase Sync (NEW - doesn't affect existing timer logic)
    @available(iOS 16.1, *)
    private func saveLiveActivityStateToFirebase(roomId: String, roomName: String, endTime: Date, duration: TimeInterval, isActive: Bool) {
        let dbRef = Database.database().reference()
        let liveActivityData: [String: Any] = [
            "isActive": isActive,
            "endTime": ISO8601DateFormatter().string(from: endTime),
            "roomName": roomName,
            "duration": duration,
            "lastUpdated": ServerValue.timestamp()
        ]
        
        dbRef.child("rooms").child(roomId).child("liveActivity").setValue(liveActivityData) { error, _ in
            if let error = error {
                print("Failed to save Live Activity state: \(error)")
                self.logToFile("Failed to save Live Activity state: \(error)")
            } else {
                print("Saved Live Activity state for room \(roomId)")
                self.logToFile("Saved Live Activity state for room \(roomId)")
            }
        }
    }

    @available(iOS 16.1, *)
    private func clearLiveActivityStateFromFirebase(roomId: String) {
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(roomId).child("liveActivity").removeValue { error, _ in
            if let error = error {
                print("Failed to clear Live Activity state: \(error)")
                self.logToFile("Failed to clear Live Activity state: \(error)")
            } else {
                print("Cleared Live Activity state for room \(roomId)")
                self.logToFile("Cleared Live Activity state for room \(roomId)")
            }
        }
    }

    @available(iOS 16.1, *)
    func setupLiveActivityObserver() {
        guard let currentRoomId = currentRoomId else { return }
        
        let dbRef = Database.database().reference()
        dbRef.child("rooms").child(currentRoomId).child("liveActivity").observe(.value) { snapshot in
            if let liveActivityData = snapshot.value as? [String: Any],
               let isActive = liveActivityData["isActive"] as? Bool,
               let endTimeStr = liveActivityData["endTime"] as? String,
               let endTime = ISO8601DateFormatter().date(from: endTimeStr),
               let roomName = liveActivityData["roomName"] as? String,
               let duration = liveActivityData["duration"] as? TimeInterval,
               isActive && endTime > Date() {
                
                // Start Live Activity for this user
                DispatchQueue.main.async {
                    self.startLiveActivityForUser(roomId: currentRoomId, roomName: roomName, endTime: endTime, duration: duration)
                }
            } else {
                // Clear Live Activity for this user
                DispatchQueue.main.async {
                    self.endLiveActivityForUser(roomId: currentRoomId)
                }
            }
        }
    }

    @available(iOS 16.1, *)
    private func startLiveActivityForUser(roomId: String, roomName: String, endTime: Date, duration: TimeInterval) {
        // Check if Live Activity is already running for this room
        let activities = Activity<TreatmentTimerAttributes>.activities
        let existingActivity = activities.first { $0.attributes.roomId == roomId && $0.activityState == .active }
        
        if existingActivity != nil {
            print("Live Activity already exists for room \(roomId)")
            return
        }
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }
        
        let attributes = TreatmentTimerAttributes(roomName: roomName, roomId: roomId)
        let contentState = TreatmentTimerAttributes.ContentState(
            endTime: endTime,
            isActive: true,
            totalDuration: duration
        )
        
        do {
            let activity = try Activity<TreatmentTimerAttributes>.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            print("Live Activity started for user in room: \(roomId)")
            logToFile("Live Activity started for user in room: \(roomId)")
        } catch {
            print("Error starting Live Activity for user: \(error)")
            logToFile("Error starting Live Activity for user: \(error)")
        }
    }

    @available(iOS 16.1, *)
    func endLiveActivityForUser(roomId: String) {
        let activities = Activity<TreatmentTimerAttributes>.activities
        
        for activity in activities {
            if activity.attributes.roomId == roomId && activity.activityState == .active {
                let expiredContentState = TreatmentTimerAttributes.ContentState(
                    endTime: Date(),
                    isActive: false,
                    totalDuration: 900.0
                )
                
                Task {
                    await activity.end(using: expiredContentState, dismissalPolicy: .immediate)
                }
                print("Live Activity ended for user in room: \(roomId)")
                logToFile("Live Activity ended for user in room: \(roomId)")
                break
            }
        }
    }
    
    // MARK: - Demo Room Code Methods (Super Admin Only)
    func createDemoRoomCode(customCode: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser,
              currentUser.isSuperAdmin,
              let roomId = currentRoomId else {
            completion(false, "Super admin access required")
            return
        }
        
        // Generate code if none provided
        let code = customCode?.uppercased() ?? generateRandomCode()
        
        // Validate code format (6 characters, alphanumeric)
        let isValidFormat = code.count == 6 && code.allSatisfy { $0.isLetter || $0.isNumber }
        guard isValidFormat else {
            completion(false, "Code must be exactly 6 alphanumeric characters")
            return
        }
        
        // Get room name
        let roomName = cycles.last?.patientName.isEmpty == false ?
            "\(cycles.last?.patientName ?? "Unknown")'s Program" : "Demo Room"
        
        let dbRef = Database.database().reference()
        
        // Check if code already exists globally
        checkIfDemoCodeExists(code: code) { exists in
            if exists {
                completion(false, "Code already exists. Please choose a different code.")
                return
            }
            
            // Create demo room code
            let demoCode = DemoRoomCode(
                roomId: roomId,
                code: code,
                createdBy: currentUser.id,
                roomName: roomName
            )
            
            // Save to Firebase
            dbRef.child("demoRoomCodes").child(roomId).setValue(demoCode.toDictionary()) { error, _ in
                if let error = error {
                    completion(false, "Failed to create demo code: \(error.localizedDescription)")
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    func toggleDemoRoomCode(isActive: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let currentUser = currentUser,
              currentUser.isSuperAdmin,
              let roomId = currentRoomId else {
            completion(false, "Super admin access required")
            return
        }
        
        let dbRef = Database.database().reference()
        
        if isActive {
            // Check if demo code exists for this room
            dbRef.child("demoRoomCodes").child(roomId).observeSingleEvent(of: .value) { snapshot in
                if snapshot.exists() {
                    // Update existing code to active
                    dbRef.child("demoRoomCodes").child(roomId).child("isActive").setValue(true) { error, _ in
                        completion(error == nil, error?.localizedDescription)
                    }
                } else {
                    // Create new demo code
                    self.createDemoRoomCode { success, error in
                        completion(success, error)
                    }
                }
            }
        } else {
            // Disable existing code
            dbRef.child("demoRoomCodes").child(roomId).child("isActive").setValue(false) { error, _ in
                completion(error == nil, error?.localizedDescription)
            }
        }
    }

    func getDemoRoomCodeStatus(completion: @escaping (DemoRoomCode?) -> Void) {
        guard let roomId = currentRoomId else {
            completion(nil)
            return
        }
        
        let dbRef = Database.database().reference()
        dbRef.child("demoRoomCodes").child(roomId).observeSingleEvent(of: .value) { snapshot in
            if let data = snapshot.value as? [String: Any],
               let demoCode = DemoRoomCode(dictionary: data) {
                completion(demoCode)
            } else {
                completion(nil)
            }
        }
    }

    private func checkIfDemoCodeExists(code: String, completion: @escaping (Bool) -> Void) {
        let dbRef = Database.database().reference()
        
        // Check both regular invitations and demo codes
        let group = DispatchGroup()
        var codeExists = false
        
        // Check regular invitations
        group.enter()
        dbRef.child("invitations").child(code).observeSingleEvent(of: .value) { snapshot in
            if snapshot.exists() {
                codeExists = true
            }
            group.leave()
        }
        
        // Check demo room codes
        group.enter()
        dbRef.child("demoRoomCodes").observeSingleEvent(of: .value) { snapshot in
            if let allDemoCodes = snapshot.value as? [String: [String: Any]] {
                for (_, demoCodeData) in allDemoCodes {
                    if let existingCode = demoCodeData["code"] as? String,
                       existingCode.uppercased() == code.uppercased() {
                        codeExists = true
                        break
                    }
                }
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(codeExists)
        }
    }

    private func generateRandomCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}

struct TimerState: Codable {
    let timer: TreatmentTimer?
}

extension AppData {
    // This method logs a consumption for a specific item without triggering group logging behavior
    // Add or replace this method in your AppData extension
    func logIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let calendar = Calendar.current
        let logDay = calendar.startOfDay(for: date)
        
        // Check if the item already has a log for this day locally
        if let existingLogs = consumptionLog[cycleId]?[itemId] {
            let existingLogForDay = existingLogs.first { calendar.isDate($0.date, inSameDayAs: logDay) }
            if existingLogForDay != nil {
                // print("Item \(itemId) already has a log for \(logDay), skipping")
                return
            }
        }
        
        // Fetch current logs from Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            
            // Deduplicate entries by day in case there are already duplicates in Firebase
            var entriesByDay = [String: [String: String]]()
            
            for entry in currentLogs {
                if let entryTimestamp = entry["timestamp"],
                   let entryDate = formatter.date(from: entryTimestamp) {
                    let dayKey = formatter.string(from: calendar.startOfDay(for: entryDate))
                    entriesByDay[dayKey] = entry
                }
            }
            
            // Check if there's already an entry for this day
            let todayKey = formatter.string(from: logDay)
            if entriesByDay[todayKey] != nil {
                // print("Firebase already has an entry for \(logDay), skipping")
                return
            }
            
            // Add new entry
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            entriesByDay[todayKey] = newEntryDict
            
            // Convert back to array
            let deduplicatedLogs = Array(entriesByDay.values)
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(deduplicatedLogs) { error, _ in
                if let error = error {
                    // print("Error logging consumption for \(itemId): \(error)")
                    self.logToFile("Error logging consumption for \(itemId): \(error)")
                } else {
                    // Update local data after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            if var itemLogs = cycleLog[itemId] {
                                // Remove any existing logs for the same day before adding the new one
                                itemLogs.removeAll { calendar.isDate($0.date, inSameDayAs: logDay) }
                                itemLogs.append(logEntry)
                                cycleLog[itemId] = itemLogs
                            } else {
                                cycleLog[itemId] = [logEntry]
                            }
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func deleteRoom(roomId: String, completion: @escaping (Bool, String?) -> Void) {
        let dbRef = Database.database().reference()

        // First, get all users with access to this room to update their room access and settings
        dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
            if let usersData = snapshot.value as? [String: [String: Any]] {
                for (userId, userData) in usersData {
                    if let roomAccess = userData["roomAccess"] as? [String: Any],
                       roomAccess[roomId] != nil {
                        // Remove this room from user's access
                        dbRef.child("users").child(userId).child("roomAccess").child(roomId).removeValue()
                        
                        // Also remove room settings for this room
                        dbRef.child("users").child(userId).child("roomSettings").child(roomId).removeValue()
                    }
                    // Update ownedRooms for the owner
                    if userId == self.currentUser?.id.uuidString,
                       let ownedRooms = userData["ownedRooms"] as? [String] {
                        let updatedOwnedRooms = ownedRooms.filter { $0 != roomId }
                        dbRef.child("users").child(userId).child("ownedRooms").setValue(updatedOwnedRooms.isEmpty ? nil : updatedOwnedRooms)
                        DispatchQueue.main.async {
                            if var currentUser = self.currentUser {
                                currentUser.ownedRooms = updatedOwnedRooms.isEmpty ? nil : updatedOwnedRooms
                                self.currentUser = currentUser
                            }
                        }
                    }
                }

                // Now delete the room itself
                dbRef.child("rooms").child(roomId).removeValue { error, _ in
                    if let error = error {
                        // print("Error deleting room: \(error.localizedDescription)")
                        completion(false, "Failed to delete room: \(error.localizedDescription)")
                    } else {
                        // print("Room deleted successfully")
                        // If current room was deleted, clear it
                        if roomId == self.currentRoomId {
                            DispatchQueue.main.async {
                                self.currentRoomId = nil
                                UserDefaults.standard.removeObject(forKey: "currentRoomId")
                            }
                        }

                        NotificationCenter.default.post(name: Notification.Name("RoomDeleted"), object: nil)
                        NotificationCenter.default.post(name: Notification.Name("RoomLeft"), object: nil)
                        completion(true, nil)
                    }
                }
            } else {
                completion(false, "Could not get user list to update room access")
            }
        }
    }
    
    func updateRoomActivity() {
        guard let roomId = currentRoomId else { return }
        let dbRef = Database.database().reference()
        
        // Update last activity timestamp
        dbRef.child("rooms").child(roomId).child("lastActivity").setValue(ServerValue.timestamp()) { error, _ in
            if let error = error {
                // print("Failed to update room activity: \(error)")
            } else {
                // print("Updated activity for room: \(roomId)")
            }
        }
    }

    func cleanupInactiveRooms() {
        guard let userId = currentUser?.id.uuidString else { return }
        let dbRef = Database.database().reference()
        
        // print("Starting cleanup of inactive rooms for user: \(userId)")
        
        // Get all rooms user has access to
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            guard let roomAccess = snapshot.value as? [String: Any] else {
                // print("No room access found for user")
                return
            }
            
            let group = DispatchGroup()
            var roomsToDelete: [String] = []
            let sixMonthsAgo = Date().addingTimeInterval(-180 * 24 * 60 * 60)
            
            for (roomId, _) in roomAccess {
                group.enter()
                dbRef.child("rooms").child(roomId).child("lastActivity").observeSingleEvent(of: .value) { activitySnapshot in
                    defer { group.leave() }
                    
                    if let lastActivityTimestamp = activitySnapshot.value as? TimeInterval {
                        let lastActivityDate = Date(timeIntervalSince1970: lastActivityTimestamp / 1000)
                        
                        if lastActivityDate < sixMonthsAgo {
                            // print("Room \(roomId) inactive for 6+ months since \(lastActivityDate), marking for deletion")
                            roomsToDelete.append(roomId)
                        } else {
                            // print("Room \(roomId) still active, last used: \(lastActivityDate)")
                        }
                    } else {
                        // No activity recorded - check if room was created more than 90 days ago
                        dbRef.child("rooms").child(roomId).child("cycles").observeSingleEvent(of: .value) { cyclesSnapshot in
                            if cyclesSnapshot.exists() {
                                // Room has data but no activity timestamp - add current timestamp
                                dbRef.child("rooms").child(roomId).child("lastActivity").setValue(ServerValue.timestamp())
                                // print("Added activity timestamp to existing room: \(roomId)")
                            } else {
                                // Empty room with no activity - mark for deletion
                                // print("Room \(roomId) has no activity or data, marking for deletion")
                                roomsToDelete.append(roomId)
                            }
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                // print("Found \(roomsToDelete.count) inactive rooms to delete")
                
                // Delete inactive rooms
                for roomId in roomsToDelete {
                    self.deleteRoom(roomId: roomId) { success, error in
                        if success {
                            // print("Auto-deleted inactive room: \(roomId)")
                            self.logToFile("Auto-deleted inactive room: \(roomId)")
                        } else {
                            // print("Failed to auto-delete room \(roomId): \(error ?? "unknown error")")
                            self.logToFile("Failed to auto-delete room \(roomId): \(error ?? "unknown error")")
                        }
                    }
                }
            }
        }
    }
    
    // This method enhances the deletion of consumption logs to ensure consistent state
    func removeIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let calendar = Calendar.current
        
        // Update local consumptionLog first
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { calendar.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
        }
        
        // Then update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                // Remove entries that match the date (could be multiple if there were duplicates)
                entries.removeAll { entry in
                    guard let entryTimestamp = entry["timestamp"],
                          let entryDate = formatter.date(from: entryTimestamp) else {
                        return false
                    }
                    return calendar.isDate(entryDate, equalTo: date, toGranularity: .second)
                }
                
                // Update or remove the entry in Firebase
                if entries.isEmpty {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).removeValue { error, _ in
                        if let error = error {
                            // print("Error removing consumption for \(itemId): \(error)")
                            self.logToFile("Error removing consumption for \(itemId): \(error)")
                        } else {
                            // print("Successfully removed all logs for item \(itemId)")
                            self.logToFile("Successfully removed all logs for item \(itemId)")
                        }
                    }
                } else {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries) { error, _ in
                        if let error = error {
                            // print("Error updating consumption for \(itemId): \(error)")
                            self.logToFile("Error updating consumption for \(itemId): \(error)")
                        } else {
                            // print("Successfully updated logs for item \(itemId)")
                            self.logToFile("Successfully updated logs for item \(itemId)")
                        }
                    }
                }
            }
        }
        
        // Ensure UI updates
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    // MARK: - Treatment Timer Override Methods
    func updateTreatmentTimerOverride(enabled: Bool, durationSeconds: Int = 900) {
        guard let dbRef = dbRef, currentUser?.isSuperAdmin == true else { return }
        
        let override = TreatmentTimerOverride(enabled: enabled, durationSeconds: durationSeconds)
        
        // Update local state immediately
        DispatchQueue.main.async {
            self.treatmentTimerOverride = override
            self.objectWillChange.send()
        }
        
        // Save to Firebase
        dbRef.child("room_settings").child("treatment_timer_override").setValue(override.toDictionary()) { error, _ in
            if let error = error {
                print("Error updating treatment timer override: \(error.localizedDescription)")
                self.logToFile("Error updating treatment timer override: \(error.localizedDescription)")
            } else {
                print("Successfully updated treatment timer override: enabled=\(enabled), duration=\(durationSeconds)")
                self.logToFile("Successfully updated treatment timer override: enabled=\(enabled), duration=\(durationSeconds)")
            }
        }
    }

    func getEffectiveTreatmentTimerDuration() -> TimeInterval {
        if treatmentTimerOverride.enabled && treatmentTimerOverride.durationSeconds > 0 {
            return TimeInterval(treatmentTimerOverride.durationSeconds)
        }
        return 900.0 // Default 15 minutes
    }

    private func loadTreatmentTimerOverride() {
        guard let dbRef = dbRef else { return }
        
        dbRef.child("room_settings").child("treatment_timer_override").observe(.value) { snapshot in
            if let data = snapshot.value as? [String: Any],
               let override = TreatmentTimerOverride(dictionary: data) {
                DispatchQueue.main.async {
                    self.treatmentTimerOverride = override
                    self.objectWillChange.send()
                }
            } else {
                // No override set, use default
                DispatchQueue.main.async {
                    self.treatmentTimerOverride = TreatmentTimerOverride()
                    self.objectWillChange.send()
                }
            }
        }
    }
}

extension AppData {
    // Method to safely access dbRef for direct Firebase operations in critical code paths
    func valueForDBRef() -> DatabaseReference? {
        return dbRef
    }
    // MARK: - Super Admin Methods
    func validateSuperAdminCode(_ code: String, completion: @escaping (Bool, String?) -> Void) {
        let remoteConfig = RemoteConfig.remoteConfig()
        
        // Fetch latest config from Firebase
        remoteConfig.fetch(withExpirationDuration: 0) { status, error in
            if status == .success {
                remoteConfig.activate { _, _ in
                    // Get comma-separated codes from Remote Config
                    let codesString = remoteConfig.configValue(forKey: "superAdminCodes").stringValue ?? ""
                    let validCodes = codesString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                    
                    let isValid = validCodes.contains(code.uppercased())
                    completion(isValid, isValid ? nil : "Invalid admin code")
                }
            }
        }
    }
    
    
        
    func applySuperAdminAccess(completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUser?.id.uuidString else {
            completion(false, "No user found")
            return
        }
        
        let dbRef = Database.database().reference()
        
        let updates: [String: Any] = [
            "subscriptionPlan": "super_admin",
            "roomLimit": 999,
            "isSuperAdmin": true,
            "superAdminActivatedDate": ISO8601DateFormatter().string(from: Date())
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                completion(false, "Failed to activate admin access: \(error.localizedDescription)")
                return
            }
            
            // Force refresh the current user data
            dbRef.child("users").child(userId).observeSingleEvent(of: .value) { snapshot in
                if let userData = snapshot.value as? [String: Any],
                   let refreshedUser = User(dictionary: userData) {
                    DispatchQueue.main.async {
                        self.currentUser = refreshedUser
                        // print("Super admin activated - isSuperAdmin: \(refreshedUser.isSuperAdmin)")
                        self.objectWillChange.send()
                        completion(true, nil)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.forceRefreshCurrentUser {
                            completion(true, nil)
                        }
                    }
                }
            }
        }
    }
    func removeSuperAdminAccess(completion: @escaping (Bool, String?) -> Void) {
        guard let userId = currentUser?.id.uuidString else {
            completion(false, "No user found")
            return
        }
        
        let dbRef = Database.database().reference()
        
        // Reset to basic subscription values
        let updates: [String: Any] = [
            "subscriptionPlan": "none",
            "roomLimit": 0,
            "isSuperAdmin": false,
            "superAdminRemovedDate": ISO8601DateFormatter().string(from: Date())
        ]
        
        dbRef.child("users").child(userId).updateChildValues(updates) { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    completion(false, "Failed to remove admin access: \(error.localizedDescription)")
                }
                return
            }
            
            // Force refresh the current user data safely
            DispatchQueue.main.async {
                self.forceRefreshCurrentUser {
                    completion(true, nil)
                }
            }
        }
    }
}
