import Foundation
import FirebaseAuth
import Combine
import FirebaseDatabase

class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: AuthUser?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var showingNameInput = false
    @Published var pendingAppleSignInResult: AppleSignInResult?
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let appleSignInManager = AppleSignInManager()
    
    init() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            // print("Auth state changed. User: \(user?.uid ?? "nil")")
            
            if let user = user {
                self.currentUser = AuthUser(user: user)
                self.authState = .signedIn
                // print("User signed in: \(user.uid)")
            } else {
                self.currentUser = nil
                self.authState = .signedOut
                // print("User signed out")
            }
        }
    }
    
    deinit {
        if let authStateHandler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(authStateHandler)
        }
    }
    
    func signInWithApple() {
        // print("Starting Apple Sign In")
        isProcessing = true
        errorMessage = nil
        
        appleSignInManager.signInWithApple { [weak self] result in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                switch result {
                case .success(let appleResult):
                    // print("Apple Sign In successful, handling result")
                    self?.handleAppleSignInResult(appleResult)
                case .failure(let error):
                    // print("Apple Sign In failed: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func handleAppleSignInResult(_ result: AppleSignInResult) {
        // print("Handling Apple Sign In result for encoded ID: \(result.encodedAppleUserID)")
        
        // Check if this Apple ID already has an account using encoded ID
        checkForExistingAppleAccount(appleUserID: result.encodedAppleUserID) { [weak self] existingUser in
            DispatchQueue.main.async {
                if let existingUser = existingUser {
                    // print("Found existing user: \(existingUser.name)")
                    // User already exists, sign them in
                    self?.completeSignIn(existingUser: existingUser, result: result)
                } else {
                    // print("No existing user found, creating new account")
                    // New user, check if we have a name
                    if let displayName = result.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // print("Using name from Apple: \(displayName)")
                        // We have a name from Apple, but still need email - show name input pre-filled
                        self?.pendingAppleSignInResult = result
                        self?.showingNameInput = true
                    } else {
                        // print("No name from Apple, showing name input")
                        // No name from Apple, show name input
                        self?.pendingAppleSignInResult = result
                        self?.showingNameInput = true
                    }
                }
            }
        }
    }
    
    func completeNameInput(name: String, email: String) {
        guard let result = pendingAppleSignInResult else {
            // print("No pending Apple sign in result")
            return
        }
        
        // print("Completing name input with name: \(name) and email: \(email)")
        showingNameInput = false
        pendingAppleSignInResult = nil
        
        // Add a small delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.createNewAccount(with: result, name: name, email: email)
        }
    }
    
    private func checkForExistingAppleAccount(appleUserID: String, completion: @escaping (User?) -> Void) {
        let dbRef = Database.database().reference()
        
        // print("Checking for existing account with ID: \(appleUserID)")
        
        // Check if Apple ID exists in auth_mapping
        dbRef.child("auth_mapping").child(appleUserID).observeSingleEvent(of: .value) { snapshot in
            // print("Auth mapping check result: exists=\(snapshot.exists())")
            
            guard let userIdString = snapshot.value as? String,
                  let userId = UUID(uuidString: userIdString) else {
                // print("No existing mapping found")
                completion(nil)
                return
            }
            
            // print("Found mapping to user ID: \(userIdString)")
            
            // Get the user data
            dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { userSnapshot in
                // print("User data check result: exists=\(userSnapshot.exists())")
                
                guard let userData = userSnapshot.value as? [String: Any],
                      let user = User(dictionary: userData) else {
                    // print("Failed to load user data")
                    completion(nil)
                    return
                }
                
                // print("Successfully loaded existing user: \(user.name)")
                completion(user)
            }
        }
    }
    
    private func completeSignIn(existingUser: User, result: AppleSignInResult) {
        // print("Completing sign in for existing user: \(existingUser.name)")
        
        // Post notification immediately with the existing user
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("AuthUserSignedIn"),
                object: nil,
                userInfo: ["authUser": self.currentUser as Any, "appUser": existingUser]
            )
            
            // print("Posted AuthUserSignedIn notification for existing user: \(existingUser.name)")
        }
        
        checkAndShowOnboarding()
    }
    
    private func createNewAccount(with result: AppleSignInResult, name: String, email: String) {
        // print("Creating new account with name: \(name) and email: \(email)")
        
        let userId = UUID()
        let userIdString = userId.uuidString
        
        // Create the app user with the name and email from NameInputView
        let newUser = User(
            id: userId,
            name: name,
            email: email, // NEW: Include email
            authId: result.appleUserID,
            ownedRooms: nil,
            subscriptionPlan: nil,
            roomLimit: 0,
            isSuperAdmin: false,
            pendingTransferRequests: nil,
            roomAccess: nil,  // Start with empty room access
            roomSettings: nil,  // Start with empty room settings
            appVersionHistory: nil // NEW: Will be populated by AppVersionTracker
        )
        
        let dbRef = Database.database().reference()
        
        // print("Saving auth mapping: \(result.encodedAppleUserID) -> \(userIdString)")
        
        // Save auth mapping: Encoded Apple ID -> App User ID
        dbRef.child("auth_mapping").child(result.encodedAppleUserID).setValue(userIdString) { error, _ in
            if let error = error {
                // print("Error creating auth mapping: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create account: \(error.localizedDescription)"
                }
                return
            }
            
            // print("Auth mapping saved successfully")
            
            // Save user data with the correct name, email and new structure
            dbRef.child("users").child(userIdString).setValue(newUser.toDictionary()) { error, _ in
                if let error = error {
                    // print("Error creating user: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to create user data: \(error.localizedDescription)"
                    }
                } else {
                    // print("Successfully created user with name: \(name) and email: \(email) for Apple ID: \(result.appleUserID)")
                    UserDefaults.standard.set(userIdString, forKey: "currentUserId")
                    
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("AuthUserSignedIn"),
                            object: nil,
                            userInfo: ["authUser": self.currentUser as Any, "appUser": newUser]
                        )
                        
                        // print("Posted AuthUserSignedIn notification for new user: \(newUser.name)")
                    }
                    
                    self.checkAndShowOnboarding()
                }
            }
        }
    }
    
    
    func checkAndShowOnboarding() {
        // Post a delayed notification so it happens after the user is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowOnboardingTutorial"),
                    object: nil
                )
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.authState = .signedOut
            self.currentUser = nil
            self.showingNameInput = false
            self.pendingAppleSignInResult = nil
            self.errorMessage = nil
            // print("User signed out successfully")
        } catch {
            self.errorMessage = "Error signing out: \(error.localizedDescription)"
            // print("Sign out error: \(error.localizedDescription)")
        }
    }
    
    func deleteAccount(completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "No user is signed in")
            return
        }
        
        // Get user data before deletion
        guard let currentAppUser = self.currentUser else {
            completion(false, "User data not found")
            return
        }
        
        let dbRef = Database.database().reference()
        let userIdString = currentAppUser.uid
        
        // Step 1: Get Apple ID for auth mapping cleanup
        var appleId: String?
        for provider in user.providerData {
            if provider.providerID == "apple.com" {
                appleId = provider.uid
                break
            }
        }
        
        // Step 2: Get user's owned rooms and delete them
        dbRef.child("users").child(userIdString).observeSingleEvent(of: .value) { snapshot in
            guard let userData = snapshot.value as? [String: Any] else {
                completion(false, "Could not fetch user data")
                return
            }
            
            let ownedRooms = userData["ownedRooms"] as? [String] ?? []
            let group = DispatchGroup()
            
            // Delete all owned rooms
            for roomId in ownedRooms {
                group.enter()
                
                // Get all users in this room to update their room access
                dbRef.child("rooms").child(roomId).child("users").observeSingleEvent(of: .value) { roomSnapshot in
                    if let roomUsers = roomSnapshot.value as? [String: Any] {
                        // Remove room access for all users in this room
                        for (userId, _) in roomUsers {
                            dbRef.child("users").child(userId).child("roomAccess").child(roomId).removeValue()
                        }
                    }
                    
                    // Delete the entire room
                    dbRef.child("rooms").child(roomId).removeValue { error, _ in
                        if let error = error {
                            // print("Error deleting owned room \(roomId): \(error.localizedDescription)")
                        } else {
                            // print("Successfully deleted owned room: \(roomId)")
                        }
                        group.leave()
                    }
                }
            }
            
            // Step 3: Remove user from any rooms they were invited to (but don't delete those rooms)
            if let roomAccess = userData["roomAccess"] as? [String: Any] {
                for (roomId, _) in roomAccess {
                    if !ownedRooms.contains(roomId) {
                        group.enter()
                        // Remove user from this room's users list
                        dbRef.child("rooms").child(roomId).child("users").child(userIdString).removeValue { error, _ in
                            if let error = error {
                                // print("Error removing user from room \(roomId): \(error.localizedDescription)")
                            } else {
                                // print("Successfully removed user from room: \(roomId)")
                            }
                            group.leave()
                        }
                    }
                }
            }
            
            // Step 4: When all room operations complete, delete user data and auth
            group.notify(queue: .main) {
                // Delete auth mapping if Apple ID exists
                if let appleUserId = appleId {
                    let encodedAppleId = self.encodeForFirebase(appleUserId)
                    dbRef.child("auth_mapping").child(encodedAppleId).removeValue { error, _ in
                        if let error = error {
                            // print("Error deleting auth mapping: \(error.localizedDescription)")
                        } else {
                            // print("Successfully deleted auth mapping")
                        }
                    }
                }
                
                // Delete user node from Firebase
                dbRef.child("users").child(userIdString).removeValue { error, _ in
                    if let error = error {
                        // print("Error deleting user data: \(error.localizedDescription)")
                        completion(false, "Failed to delete user data: \(error.localizedDescription)")
                        return
                    }
                    
                    // print("Successfully deleted user data from Firebase")
                    
                    // Delete Firebase Auth account
                    user.delete { error in
                        if let error = error {
                            // print("Error deleting Firebase Auth account: \(error.localizedDescription)")
                            completion(false, "Failed to delete account: \(error.localizedDescription)")
                        } else {
                            // print("Successfully deleted Firebase Auth account")
                            
                            // Clear local data
                            self.signOut()
                            
                            // Clear all UserDefaults
                            let defaults = UserDefaults.standard
                            defaults.removeObject(forKey: "currentUserId")
                            defaults.removeObject(forKey: "currentRoomId")
                            defaults.removeObject(forKey: "roomCode")
                            defaults.removeObject(forKey: "hasAcceptedPrivacyPolicy")
                            defaults.removeObject(forKey: "hasCompletedOnboarding")
                            defaults.removeObject(forKey: "treatmentTimerState")
                            defaults.removeObject(forKey: "cachedCycles")
                            defaults.removeObject(forKey: "cachedCycleItems")
                            defaults.removeObject(forKey: "cachedGroupedItems")
                            defaults.removeObject(forKey: "cachedConsumptionLog")
                            defaults.synchronize()
                            
                            // print("Account and all associated data successfully deleted")
                            completion(true, nil)
                        }
                    }
                }
            }
        }
    }
    
    private func encodeForFirebase(_ string: String) -> String {
        return string
            .replacingOccurrences(of: ".", with: "_DOT_")
            .replacingOccurrences(of: "#", with: "_HASH_")
            .replacingOccurrences(of: "$", with: "_DOLLAR_")
            .replacingOccurrences(of: "[", with: "_LBRACKET_")
            .replacingOccurrences(of: "]", with: "_RBRACKET_")
    }
}
