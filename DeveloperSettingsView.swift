//
//  DeveloperSettingsView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/24/25.
//

import SwiftUI
import FirebaseDatabase
import TelemetryDeck

struct DeveloperSettingsView: View {
    @ObservedObject var appData: AppData
    @State private var roomId = ""
    @State private var isValidating = false
    @State private var showingConfirmation = false
    @State private var roomName = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var timerOverrideEnabled = false
    @State private var customTimerDuration = "900"
    @State private var hasLoadedSettings = false
    
    // Demo Room Code states
    @State private var demoCodeEnabled = false
    @State private var currentDemoCode = ""
    @State private var customDemoCode = ""
    @State private var usageCount = 0
    @State private var isCreatingDemoCode = false
    @State private var showingDemoCodeSuccess = false
    @State private var demoCodeSuccessMessage = ""
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Developer Tools")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Super Admin Developer Access")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Demo Room Code Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.green)
                            Text("DEMO ROOM ACCESS")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            if let currentRoomName = getCurrentRoomDisplayName() {
                                Text("Current Room: \(currentRoomName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Toggle("Enable Demo Code for This Room", isOn: $demoCodeEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .onChange(of: demoCodeEnabled) { newValue in
                                    toggleDemoCode(enabled: newValue)
                                }
                            
                            if demoCodeEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    if !currentDemoCode.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Active Demo Code:")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            
                                            Text(currentDemoCode)
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            
                                            Text("Usage Count: \(usageCount)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    
                                    Text("Create New Demo Code:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        TextField("Custom Code (6 chars)", text: $customDemoCode)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .autocapitalization(.allCharacters)
                                            .disableAutocorrection(true)
                                            .font(.system(.body, design: .monospaced))
                                            .onChange(of: customDemoCode) { newValue in
                                                // Limit to 6 characters and alphanumeric only
                                                let filtered = String(newValue.prefix(6).filter { $0.isLetter || $0.isNumber })
                                                if filtered != newValue {
                                                    customDemoCode = filtered
                                                }
                                            }
                                        
                                        Button(action: generateRandomDemoCode) {
                                            Text("Generate")
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    Button(action: createNewDemoCode) {
                                        HStack {
                                            if isCreatingDemoCode {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .foregroundColor(.white)
                                            }
                                            Text(isCreatingDemoCode ? "Creating..." : "Create Demo Code")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(customDemoCode.count == 6 ? Color.green : Color.gray)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                    }
                                    .disabled(customDemoCode.count != 6 || isCreatingDemoCode)
                                }
                            }
                            
                            Text("Demo codes allow unlimited users to join this room as admins. Users who join with demo codes will have full administrative privileges.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Treatment Timer Override Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("TREATMENT TIMER OVERRIDE")
                                .font(.headline)
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Override Treatment Timer Duration", isOn: $timerOverrideEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .purple))
                            
                            if timerOverrideEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Custom Duration (seconds)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Duration in seconds", text: $customTimerDuration)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .keyboardType(.numberPad)
                                        .font(.system(.body, design: .monospaced))
                                    
                                    Text("Default: 900 seconds (15 minutes)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let duration = Int(customTimerDuration), duration > 0 {
                                        let minutes = duration / 60
                                        let seconds = duration % 60
                                        Text("= \(minutes):\(String(format: "%02d", seconds)) (mm:ss)")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                            
                            Text("When enabled, all users in this room will use the custom timer duration for treatment foods.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Room Access Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                            Text("PRIVATE ROOM ACCESS")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        VStack(spacing: 16) {
                            TextField("Firebase Room ID", text: $roomId)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.system(.body, design: .monospaced))
                            
                            Button(action: validateRoomId) {
                                HStack {
                                    if isValidating {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .foregroundColor(.white)
                                    }
                                    Text(isValidating ? "Validating..." : "Join Room Privately")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(roomId.isEmpty ? Color.gray : Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(roomId.isEmpty || isValidating)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Confirm Room Access", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Join") {
                joinRoomPrivately()
            }
        } message: {
            Text("Join room: \(roomName)?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Demo Code Created", isPresented: $showingDemoCodeSuccess) {
            Button("OK") { }
        } message: {
            Text(demoCodeSuccessMessage)
        }
        .onAppear {
            loadSettings()
            loadDemoCodeStatus()
        }
        .onDisappear {
            saveTimerSettings()
        }
        .onChange(of: timerOverrideEnabled) { _ in
            saveTimerSettings()
        }
        .onChange(of: customTimerDuration) { _ in
            // Auto-save after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                saveTimerSettings()
            }
        }
    }
    
    private func getCurrentRoomDisplayName() -> String? {
        if let cycle = appData.cycles.last,
           !cycle.patientName.isEmpty && cycle.patientName != "Unnamed" {
            return "\(cycle.patientName)'s Program"
        }
        return appData.currentRoomId.map { "Room \(String($0.prefix(8)))" }
    }
    
    private func loadDemoCodeStatus() {
        appData.getDemoRoomCodeStatus { demoCode in
            DispatchQueue.main.async {
                if let demoCode = demoCode {
                    self.demoCodeEnabled = demoCode.isActive
                    self.currentDemoCode = demoCode.code
                    self.usageCount = demoCode.usageCount
                } else {
                    self.demoCodeEnabled = false
                    self.currentDemoCode = ""
                    self.usageCount = 0
                }
            }
        }
    }
    
    private func toggleDemoCode(enabled: Bool) {
        appData.toggleDemoRoomCode(isActive: enabled) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.loadDemoCodeStatus() // Refresh status
                } else {
                    self.errorMessage = error ?? "Failed to toggle demo code"
                    self.showingError = true
                    self.demoCodeEnabled = !enabled // Revert toggle
                }
            }
        }
    }
    
    private func generateRandomDemoCode() {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        customDemoCode = String((0..<6).map { _ in characters.randomElement()! })
    }
    
    private func createNewDemoCode() {
        guard customDemoCode.count == 6 else { return }
        
        isCreatingDemoCode = true
        
        appData.createDemoRoomCode(customCode: customDemoCode) { success, error in
            DispatchQueue.main.async {
                self.isCreatingDemoCode = false
                
                if success {
                    self.demoCodeSuccessMessage = "Demo code '\(self.customDemoCode)' created successfully!"
                    self.showingDemoCodeSuccess = true
                    self.customDemoCode = ""
                    self.loadDemoCodeStatus() // Refresh status
                } else {
                    self.errorMessage = error ?? "Failed to create demo code"
                    self.showingError = true
                }
            }
        }
    }
    
    private func loadSettings() {
        guard !hasLoadedSettings else { return }
        hasLoadedSettings = true
        
        timerOverrideEnabled = appData.treatmentTimerOverride.enabled
        customTimerDuration = String(appData.treatmentTimerOverride.durationSeconds)
    }
    
    private func saveTimerSettings() {
        guard hasLoadedSettings else { return }
        
        let duration = Int(customTimerDuration) ?? 900
        let validDuration = max(duration, 1) // Ensure positive
        
        // Update the text field if it was corrected
        if validDuration != duration {
            customTimerDuration = String(validDuration)
        }
        
        appData.updateTreatmentTimerOverride(
            enabled: timerOverrideEnabled,
            durationSeconds: validDuration
        )
    }
    
    private func validateRoomId() {
        guard !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let cleanRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidating = true
        let dbRef = Database.database().reference()
        
        print("DEBUG: Checking room ID: '\(cleanRoomId)'")
        
        dbRef.child("rooms").child(cleanRoomId).observeSingleEvent(of: .value) { snapshot in
            print("DEBUG: Room exists: \(snapshot.exists())")
            print("DEBUG: Snapshot key: \(snapshot.key)")
            print("DEBUG: Snapshot value exists: \(snapshot.value != nil)")
            
            guard snapshot.exists() else {
                DispatchQueue.main.async {
                    self.isValidating = false
                    self.errorMessage = "Room not found with ID: \(cleanRoomId)"
                    self.showingError = true
                }
                return
            }
            
            if let roomData = snapshot.value as? [String: Any] {
                print("DEBUG: Room data keys: \(roomData.keys)")
                
                // Try to get room name from cycles
                if let cycles = roomData["cycles"] as? [String: [String: Any]] {
                    print("DEBUG: Found \(cycles.count) cycles")
                    var latestCycle: [String: Any]? = nil
                    var latestStartDate: Date? = nil
                    
                    for (cycleId, cycleData) in cycles {
                        print("DEBUG: Checking cycle \(cycleId)")
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
                        print("DEBUG: Found patient name: \(patientName)")
                        DispatchQueue.main.async {
                            self.roomId = cleanRoomId // Update with clean ID
                            self.roomName = "\(patientName)'s Program"
                            self.isValidating = false
                            self.showingConfirmation = true
                        }
                        return
                    }
                }
                
                // Fallback to generic name
                print("DEBUG: Using fallback room name")
                DispatchQueue.main.async {
                    self.roomId = cleanRoomId // Update with clean ID
                    self.roomName = "Room \(cleanRoomId.prefix(8))"
                    self.isValidating = false
                    self.showingConfirmation = true
                }
            } else {
                DispatchQueue.main.async {
                    self.isValidating = false
                    self.errorMessage = "Invalid room data"
                    self.showingError = true
                }
            }
        }
    }
    
    private func joinRoomPrivately() {
        guard let currentUser = appData.currentUser else {
            errorMessage = "No current user"
            showingError = true
            return
        }
        
        let userId = currentUser.id.uuidString
        let dbRef = Database.database().reference()
        let joinedAt = ISO8601DateFormatter().string(from: Date())
        
        // Add room access for super admin
        dbRef.child("users").child(userId).child("roomAccess").observeSingleEvent(of: .value) { snapshot in
            var roomAccess = (snapshot.value as? [String: Any]) ?? [:]
            
            // Mark all other rooms as inactive
            for (existingRoomId, accessData) in roomAccess {
                if var accessDict = accessData as? [String: Any] {
                    accessDict["isActive"] = false
                    roomAccess[existingRoomId] = accessDict
                } else if accessData as? Bool == true {
                    roomAccess[existingRoomId] = [
                        "joinedAt": joinedAt,
                        "isActive": false
                    ]
                }
            }
            
            // Add new room as active
            roomAccess[self.roomId] = [
                "joinedAt": joinedAt,
                "isActive": true,
                "isSuperAdminAccess": true // Mark as super admin access
            ]
            
            dbRef.child("users").child(userId).child("roomAccess").setValue(roomAccess) { error, _ in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error joining room: \(error.localizedDescription)"
                        self.showingError = true
                    }
                    return
                }
                
                // Add user to room's users collection
                dbRef.child("rooms").child(self.roomId).child("users").child(userId).setValue([
                    "id": userId,
                    "name": currentUser.name,
                    "isAdmin": true,
                    "joinedAt": joinedAt,
                    "isSuperAdminAccess": true // Mark as super admin access
                ])
                
                // Update app state
                DispatchQueue.main.async {
                    self.appData.currentRoomId = self.roomId
                    UserDefaults.standard.set(self.roomId, forKey: "currentRoomId")
                    
                    // Signal successful private room join
                    TelemetryDeck.signal("super_admin_private_room_join", parameters: [
                        "room_id": self.roomId,
                        "room_name": self.roomName
                    ])
                    
                    // Post notification
                    NotificationCenter.default.post(name: Notification.Name("RoomJoined"), object: nil, userInfo: ["roomId": self.roomId])
                    
                    self.dismiss()
                }
            }
        }
    }
}
