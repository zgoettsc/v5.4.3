import SwiftUI
import UserNotifications
import FirebaseDatabase

struct RemindersView: View {
    @ObservedObject var appData: AppData
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.isInsideNavigationView) var isInsideNavigationView
    
    // Local state that gets saved on exit
    @State private var localRemindersEnabled: [Category: Bool] = [:]
    @State private var localReminderTimes: [Category: Date] = [:]
    @State private var hasLoadedSettings = false
    @State private var notificationPermissionDenied = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set daily dose reminders for each category. If items in a category are not logged by the selected time, a notification will be sent.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    if notificationPermissionDenied {
                        Text("Notifications are disabled. Enable them in Settings > Notifications > TIPs App.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 8)
            }
            
            ForEach(Category.allCases, id: \.self) { category in
                Section(header:
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundColor(category.iconColor)
                        Text(category.rawValue)
                            .foregroundColor(category.iconColor)
                    }
                ) {
                    Toggle("Daily Dose Reminder", isOn: Binding(
                        get: { localRemindersEnabled[category] ?? false },
                        set: { newValue in
                            localRemindersEnabled[category] = newValue
                            print("Toggle set \(category.rawValue) to \(newValue)")
                            
                            if newValue && localReminderTimes[category] == nil {
                                localReminderTimes[category] = defaultReminderTime()
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: category.iconColor))
                    
                    if localRemindersEnabled[category] ?? false {
                        HStack {
                            Text("Time")
                                .foregroundColor(.primary)
                            Spacer()
                            DatePicker("", selection: Binding(
                                get: { localReminderTimes[category] ?? defaultReminderTime() },
                                set: { newValue in
                                    print("DatePicker setting \(category.rawValue) to \(newValue)")
                                    localReminderTimes[category] = newValue
                                }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        }
                    }
                }
            }
        }
        .navigationTitle("Dose Reminders")
        .onAppear {
            loadSettingsFromFirebase()
            requestNotificationPermission()
            checkNotificationPermissions()
            if isInsideNavigationView {
                print("RemindersView is correctly inside a NavigationView")
            } else {
                print("Warning: RemindersView is not inside a NavigationView")
            }
        }
        .onDisappear {
            saveSettingsToFirebase()
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Notifications Required"),
                message: Text("Please enable notifications in Settings to use dose reminders."),
                primaryButton: .default(Text("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func defaultReminderTime() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? now
    }
    
    private func loadSettingsFromFirebase() {
        guard !hasLoadedSettings, let roomId = appData.currentRoomId else { return }
        
        // Force refresh user data from Firebase first
        appData.forceRefreshCurrentUser { [self] in
            guard let user = appData.currentUser else { return }
            
            // Load from room-specific settings
            let roomSettings = user.roomSettings?[roomId]
            localRemindersEnabled = roomSettings?.remindersEnabled ?? [:]
            localReminderTimes = roomSettings?.reminderTimes ?? [:]
            
            // Set default times for enabled reminders that don't have times
            for category in Category.allCases {
                if localRemindersEnabled[category] == true && localReminderTimes[category] == nil {
                    localReminderTimes[category] = defaultReminderTime()
                }
            }
            
            hasLoadedSettings = true
            print("Loaded reminder settings - enabled: \(localRemindersEnabled), times: \(localReminderTimes)")
        }
    }
    
    private func saveSettingsToFirebase() {
        guard hasLoadedSettings, var user = appData.currentUser, let roomId = appData.currentRoomId else { return }
        
        print("Saving reminder settings - enabled: \(localRemindersEnabled), times: \(localReminderTimes)")
        
        // Update room-specific settings
        var roomSettings = user.roomSettings?[roomId] ?? RoomSettings(treatmentFoodTimerEnabled: false)
        roomSettings = RoomSettings(
            treatmentFoodTimerEnabled: roomSettings.treatmentFoodTimerEnabled,
            remindersEnabled: localRemindersEnabled,
            reminderTimes: localReminderTimes
        )
        
        if user.roomSettings == nil {
            user.roomSettings = [:]
        }
        user.roomSettings![roomId] = roomSettings
        appData.currentUser = user
        
        // Save to Firebase
        appData.addUser(user)
        
        // Schedule all notifications
        scheduleAllReminders()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Notification permission granted")
                    UNUserNotificationCenter.current().delegate = UIApplication.shared.delegate as? UNUserNotificationCenterDelegate
                } else {
                    self.notificationPermissionDenied = true
                    self.showingPermissionAlert = true
                }
                if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationPermissionDenied = settings.authorizationStatus == .denied
            }
        }
    }
    
    private func scheduleAllReminders() {
        guard let roomId = appData.currentRoomId else { return }
        
        // Cancel all existing reminders for this user/room
        let userId = appData.currentUser?.id.uuidString ?? ""
        var identifiersToCancel: [String] = []
        for category in Category.allCases {
            let identifier = "reminder_\(userId)_\(category.rawValue)_\(roomId)"
            identifiersToCancel.append(identifier)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        
        // Schedule new reminders for enabled categories
        for category in Category.allCases {
            if localRemindersEnabled[category] == true, let time = localReminderTimes[category] {
                scheduleReminder(for: category, time: time, roomId: roomId)
            }
        }
    }
    
    private func scheduleReminder(for category: Category, time: Date, roomId: String) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        
        // Get the room name (patient name) for the notification
        let participantName = appData.cycles.last?.patientName ?? "TIPs Program"
        
        let content = UNMutableNotificationContent()
        content.title = "\(participantName): Dose reminder for \(category.rawValue)"
        content.body = "Have you logged all items in \(category.rawValue) for \(participantName)?"
        content.sound = .default
        content.categoryIdentifier = "REMINDER_CATEGORY"
        content.userInfo = ["roomId": roomId, "category": category.rawValue]
        content.badge = 1
        
        var triggerComponents = DateComponents()
        triggerComponents.hour = hour
        triggerComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        let identifier = "reminder_\(appData.currentUser?.id.uuidString ?? "")_\(category.rawValue)_\(roomId)"
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
}
