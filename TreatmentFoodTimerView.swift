import SwiftUI

struct TreatmentFoodTimerView: View {
    @ObservedObject var appData: AppData
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.isInsideNavigationView) var isInsideNavigationView
    
    // Local state that gets saved on exit
    @State private var isEnabled: Bool = false
    @State private var hasLoadedSettings = false
    
    init(appData: AppData) {
        self.appData = appData
    }
    
    var body: some View {
        Form {
            Section(header:
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.purple)
                    Text("TREATMENT FOOD TIMER")
                        .foregroundColor(.purple)
                }
            ) {
                Toggle("Enable Notification", isOn: $isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("When enabled, a notification will alert the user 15 minutes after a treatment food is logged. The Home tab will always display the remaining timer duration.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.vertical, 4)
                    
                    if isEnabled {
                        HStack(spacing: 20) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notification")
                                    .font(.headline)
                                Text("15 minute countdown")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Treatment Food Timer")
        .onAppear {
            loadSettingsFromFirebase()
            if isInsideNavigationView {
                print("TreatmentFoodTimerView is correctly inside a NavigationView")
            } else {
                print("Warning: TreatmentFoodTimerView is not inside a NavigationView")
            }
        }
        .onDisappear {
            saveSettingsToFirebase()
        }
    }
    
    private func loadSettingsFromFirebase() {
        guard !hasLoadedSettings, let roomId = appData.currentRoomId else { return }
        
        // Force refresh user data from Firebase first
        appData.forceRefreshCurrentUser { [self] in
            // Load from room-specific settings
            let roomSettings = appData.currentUser?.roomSettings?[roomId]
            isEnabled = roomSettings?.treatmentFoodTimerEnabled ?? false
            hasLoadedSettings = true
            print("Loaded treatment timer settings - enabled: \(isEnabled)")
        }
    }
    
    private func saveSettingsToFirebase() {
        guard hasLoadedSettings, let roomId = appData.currentRoomId else { return }
        
        print("Saving treatment timer settings - enabled: \(isEnabled)")
        
        // Update local user immediately
        guard var user = appData.currentUser else { return }
        
        // Update room-specific settings
        var roomSettings = user.roomSettings?[roomId] ?? RoomSettings(treatmentFoodTimerEnabled: false)
        roomSettings = RoomSettings(
            treatmentFoodTimerEnabled: isEnabled,
            remindersEnabled: roomSettings.remindersEnabled,
            reminderTimes: roomSettings.reminderTimes
        )
        
        if user.roomSettings == nil {
            user.roomSettings = [:]
        }
        user.roomSettings![roomId] = roomSettings
        appData.currentUser = user
        
        // Save to Firebase
        appData.addUser(user)
        
        // Cancel all treatment timers if disabled
        if !isEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }
}
