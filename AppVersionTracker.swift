//
//  AppVersionTracker.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 7/1/25.
//


//
//  AppVersionTracker.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 7/1/25.
//

import Foundation
import FirebaseDatabase

class AppVersionTracker: ObservableObject {
    
    static let shared = AppVersionTracker()
    
    private init() {}
    
    /// Check and record app version on launch
    func recordAppVersionOnLaunch(for user: User, appData: AppData) {
        print("🔍 AppVersionTracker: Starting version check for user \(user.name)")
        
        guard let currentVersion = getCurrentAppVersion() else {
            print("❌ AppVersionTracker: Could not get current app version")
            return
        }
        
        print("📱 AppVersionTracker: Current app version is \(currentVersion)")
        
        let currentDateString = getCurrentDateString()
        print("📅 AppVersionTracker: Current date string is \(currentDateString)")
        
        // Get existing version history or create new one
        var versionHistory = user.appVersionHistory ?? [:]
        print("📚 AppVersionTracker: Existing version history: \(versionHistory)")
        
        // Check if this version is already recorded
        if versionHistory[currentVersion] == nil {
            // This is a new version for this user, record it
            versionHistory[currentVersion] = currentDateString
            
            print("✅ AppVersionTracker: Recording new version \(currentVersion) for user \(user.name)")
            print("📝 AppVersionTracker: Updated version history: \(versionHistory)")
            
            // Update user with new version history
            var updatedUser = user
            updatedUser.appVersionHistory = versionHistory
            
            // Update in AppData and Firebase
            appData.addUser(updatedUser)
            
            // Also update Firebase directly to ensure it saves
            saveVersionHistoryToFirebase(userId: user.id.uuidString, versionHistory: versionHistory)
        } else {
            print("ℹ️ AppVersionTracker: Version \(currentVersion) already recorded for user \(user.name)")
        }
    }
    
    /// Get current app version from Info.plist
    private func getCurrentAppVersion() -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    /// Get current date as ISO8601 string
    private func getCurrentDateString() -> String {
        return ISO8601DateFormatter().string(from: Date())
    }
    
    /// Save version history directly to Firebase with safe key handling
    private func saveVersionHistoryToFirebase(userId: String, versionHistory: [String: String]) {
        print("💾 AppVersionTracker: Saving version history to Firebase for user \(userId)")
        
        let dbRef = Database.database().reference()
        
        // Clean and validate the version history before saving
        var safeVersionHistory: [String: String] = [:]
        
        for (version, date) in versionHistory {
            // Clean the version key to be Firebase-safe
            let cleanVersion = cleanVersionForFirebase(version)
            
            // Validate both key and value are not empty
            if !cleanVersion.isEmpty && !date.isEmpty {
                safeVersionHistory[cleanVersion] = date
                print("🔧 AppVersionTracker: Cleaned version '\(version)' -> '\(cleanVersion)' with date '\(date)'")
            } else {
                print("⚠️ AppVersionTracker: Skipping invalid version entry: '\(version)' -> '\(date)'")
            }
        }
        
        print("🛡️ AppVersionTracker: Safe version history to save: \(safeVersionHistory)")
        
        if !safeVersionHistory.isEmpty {
            dbRef.child("users").child(userId).child("appVersionHistory").setValue(safeVersionHistory) { error, _ in
                if let error = error {
                    print("❌ AppVersionTracker: Error saving version history to Firebase: \(error.localizedDescription)")
                } else {
                    print("✅ AppVersionTracker: Successfully saved version history to Firebase")
                }
            }
        } else {
            print("⚠️ AppVersionTracker: No valid version history to save")
        }
    }

    /// Clean version string to be Firebase-safe
    private func cleanVersionForFirebase(_ version: String) -> String {
        return version
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "#", with: "_")
            .replacingOccurrences(of: "$", with: "_")
            .replacingOccurrences(of: "[", with: "_")
            .replacingOccurrences(of: "]", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get users with specific app version (for admin use)
    func getUsersWithVersion(_ version: String, completion: @escaping ([User]) -> Void) {
        let dbRef = Database.database().reference()
        
        dbRef.child("users").observeSingleEvent(of: .value) { snapshot in
            var usersWithVersion: [User] = []
            
            guard let usersData = snapshot.value as? [String: [String: Any]] else {
                completion(usersWithVersion)
                return
            }
            
            for (_, userData) in usersData {
                if let user = User(dictionary: userData),
                   let versionHistory = user.appVersionHistory,
                   versionHistory.keys.contains(version) {
                    usersWithVersion.append(user)
                }
            }
            
            completion(usersWithVersion)
        }
    }
}
