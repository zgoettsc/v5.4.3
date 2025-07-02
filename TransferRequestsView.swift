
import SwiftUI
import TelemetryDeck
import FirebaseDatabase

struct TransferRequestsView: View {
    @ObservedObject var appData: AppData
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var processingRequests: Set<UUID> = []
    @State private var isProcessingAnyRequest = false
    @State private var navigateToManageRooms = false

    var body: some View {
        VStack {
            NavigationLink(
                destination: ManageRoomsAndSubscriptionsView(appData: appData),
                isActive: $navigateToManageRooms
            ) {
                EmptyView()
            }
            
            if appData.transferRequests.isEmpty && appData.sentTransferRequests.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No Transfer Requests")
                        .font(.headline)
                    Text("You don't have any transfer requests.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !appData.transferRequests.isEmpty {
                        Section("Incoming Requests") {
                            ForEach(appData.transferRequests) { request in
                                IncomingTransferRequestRow(
                                    request: request,
                                    appData: appData,
                                    onAccept: {
                                        appData.logToFile("Initiating accept for request \(request.id.uuidString), new owner: \(request.newOwnerId.uuidString)")
                                        appData.acceptTransferRequest(requestId: request.id) { success, error in
                                            DispatchQueue.main.async {
                                                if !success {
                                                    self.errorMessage = error ?? "Failed to accept transfer"
                                                    self.showError = true
                                                    appData.logToFile("Accept failed: \(error ?? "unknown")")
                                                } else {
                                                    self.navigateToManageRooms = true
                                                    appData.logToFile("Accept succeeded")
                                                }
                                            }
                                        }
                                    },
                                    onDecline: {
                                        declineRequest(request)
                                    }
                                )
                                .disabled(isProcessingAnyRequest)
                            }
                            .onDelete { indexSet in
                                deleteIncomingRequests(at: indexSet)
                            }
                        }
                    }
                    
                    if !appData.sentTransferRequests.isEmpty {
                        Section("Sent Requests") {
                            ForEach(appData.sentTransferRequests) { request in
                                SentTransferRequestRow(
                                    request: request,
                                    appData: appData,
                                    onCancel: { cancelRequest(request) },
                                    onResend: { resendRequest(request) }
                                )
                            }
                            .onDelete { indexSet in
                                deleteSentRequests(at: indexSet)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfer Requests")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasAnyRequests {
                    Button("Clear All") {
                        clearExpiredRequests()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            appData.loadTransferRequests()
            appData.loadSentTransferRequests()
            appData.logToFile("TransferRequestsView appeared")
        }
        .refreshable {
            appData.loadTransferRequests()
            appData.loadSentTransferRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OwnershipChanged"))) { notification in
            appData.logToFile("Received OwnershipChanged notification: \(notification.userInfo ?? [:])")
            appData.loadTransferRequests()
            appData.loadSentTransferRequests()
            appData.globalRefresh()
            if let userInfo = notification.userInfo,
               let newOwnerId = userInfo["newOwnerId"] as? String,
               newOwnerId == appData.currentUser?.id.uuidString {
                navigateToManageRooms = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }
    
    private func declineRequest(_ request: TransferRequest) {
        guard !processingRequests.contains(request.id) else {
            appData.logToFile("Request \(request.id.uuidString) already being processed, ignoring")
            return
        }
        
        processingRequests.insert(request.id)
        isProcessingAnyRequest = true
        appData.logToFile("Declining request \(request.id.uuidString)")
        
        appData.declineTransferRequest(requestId: request.id) { success, error in
            DispatchQueue.main.async {
                self.processingRequests.remove(request.id)
                self.isProcessingAnyRequest = self.processingRequests.isEmpty
                if !success {
                    self.errorMessage = error ?? "Failed to decline transfer"
                    self.showError = true
                    appData.logToFile("Decline failed: \(error ?? "unknown")")
                } else {
                    appData.logToFile("Request declined successfully")
                }
            }
        }
    }

    private func deleteIncomingRequests(at indexSet: IndexSet) {
        for index in indexSet {
            let request = appData.transferRequests[index]
            
            if request.status == .pending {
                cancelAndDeleteRequest(request)
            } else {
                deleteTransferRequest(request)
            }
        }
    }

    private func deleteSentRequests(at indexSet: IndexSet) {
        for index in indexSet {
            let request = appData.sentTransferRequests[index]
            
            if request.status == .pending {
                cancelAndDeleteRequest(request)
            } else {
                deleteTransferRequest(request)
            }
        }
    }
    
    private func cancelAndDeleteRequest(_ request: TransferRequest) {
        let dbRef = Database.database().reference()
        appData.logToFile("Cancelling and deleting request \(request.id.uuidString)")
        
        dbRef.child("transferRequests").child(request.id.uuidString).child("status").setValue("cancelled") { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to cancel request: \(error.localizedDescription)"
                    self.showError = true
                    appData.logToFile("Cancel failed: \(error.localizedDescription)")
                }
            } else {
                self.deleteTransferRequest(request)
            }
        }
    }

    private func deleteTransferRequest(_ request: TransferRequest) {
        let dbRef = Database.database().reference()
        appData.logToFile("Deleting transfer request \(request.id.uuidString)")
        
        dbRef.child("transferRequests").child(request.id.uuidString).removeValue { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to delete request: \(error.localizedDescription)"
                    self.showError = true
                    appData.logToFile("Delete failed: \(error.localizedDescription)")
                }
            } else {
                self.removeFromUserPendingRequests(request: request)
                DispatchQueue.main.async {
                    self.appData.loadTransferRequests()
                    self.appData.loadSentTransferRequests()
                }
            }
        }
    }

    private func removeFromUserPendingRequests(request: TransferRequest) {
        let dbRef = Database.database().reference()
        
        dbRef.child("users").child(request.initiatorUserId.uuidString).child("pendingTransferRequests").observeSingleEvent(of: .value) { snapshot, _ in
            if var pendingRequests = snapshot.value as? [String] {
                pendingRequests.removeAll { $0 == request.id.uuidString }
                dbRef.child("users").child(request.initiatorUserId.uuidString).child("pendingTransferRequests").setValue(pendingRequests.isEmpty ? nil : pendingRequests)
            }
        }
        
        dbRef.child("users").child(request.recipientUserId.uuidString).child("pendingTransferRequests").observeSingleEvent(of: .value) { snapshot, _ in
            if var pendingRequests = snapshot.value as? [String] {
                pendingRequests.removeAll { $0 == request.id.uuidString }
                dbRef.child("users").child(request.recipientUserId.uuidString).child("pendingTransferRequests").setValue(pendingRequests.isEmpty ? nil : pendingRequests)
            }
        }
    }

    private func cancelRequest(_ request: TransferRequest) {
        appData.cancelTransferRequest(requestId: request.id) { success, error in
            DispatchQueue.main.async {
                if !success {
                    self.errorMessage = error ?? "Failed to cancel request"
                    self.showError = true
                }
            }
        }
    }

    private func resendRequest(_ request: TransferRequest) {
        appData.cancelTransferRequest(requestId: request.id) { success, error in
            if success {
                appData.sendOwnerTransferRequest(
                    roomId: request.roomId,
                    roomName: request.roomName,
                    toUserId: request.recipientUserId
                ) { success, error in
                    DispatchQueue.main.async {
                        if !success {
                            self.errorMessage = error ?? "Failed to resend request"
                            self.showError = true
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = error ?? "Failed to cancel old request"
                    self.showError = true
                }
            }
        }
    }

    private var hasExpiredRequests: Bool {
        return !appData.transferRequests.isEmpty || !appData.sentTransferRequests.isEmpty
    }
    
    private func clearExpiredRequests() {
        let requestsToDelete = appData.transferRequests + appData.sentTransferRequests
        
        for request in requestsToDelete {
            if request.status == .pending {
                cancelAndDeleteRequest(request)
            } else {
                deleteTransferRequest(request)
            }
        }
    }

    private var hasAnyRequests: Bool {
        return !appData.transferRequests.isEmpty || !appData.sentTransferRequests.isEmpty
    }
}

struct IncomingTransferRequestRow: View {
    let request: TransferRequest
    @ObservedObject var appData: AppData
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var requesterUser: User?
    @State private var recipientUser: User?
    @State private var errorMessage: String?

    private var timeRemaining: String {
        if request.isExpired {
            return "Expired"
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour], from: Date(), to: request.expiresAt)
        
        if let days = components.day, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
        } else {
            return "Expires soon"
        }
    }
    
    private var canAccept: Bool {
        guard request.canBeAccepted else {
            appData.logToFile("Request \(request.id.uuidString) not acceptable - status: \(request.status.rawValue)")
            return false
        }
        
        // Check the new owner's capacity (newOwnerId)
        guard let newOwnerUser = appData.users.first(where: { $0.id == request.newOwnerId }) else {
            appData.logToFile("New owner user not found: \(request.newOwnerId.uuidString)")
            return false
        }
        
        let roomCount = newOwnerUser.ownedRooms?.count ?? 0
        let roomLimit = newOwnerUser.roomLimit
        let canAcceptResult = roomCount < roomLimit && roomLimit > 0
        
        appData.logToFile("New owner \(newOwnerUser.name) capacity - rooms: \(roomCount)/\(roomLimit), canAccept: \(canAcceptResult)")
        
        return canAcceptResult
    }

    private var subscriptionInfo: String {
        guard let newOwnerUser = appData.users.first(where: { $0.id == request.newOwnerId }) else {
            return "Loading..."
        }
        
        let roomCount = newOwnerUser.ownedRooms?.count ?? 0
        let roomLimit = newOwnerUser.roomLimit
        return "\(roomCount)/\(roomLimit)"
    }

    private var subscriptionWarning: String? {
        if !request.canBeAccepted {
            return "This request is \(request.status.rawValue) and cannot be accepted."
        }
        
        guard let newOwnerUser = appData.users.first(where: { $0.id == request.newOwnerId }) else {
            return errorMessage ?? "Unable to load new owner's data."
        }
        
        let roomCount = newOwnerUser.ownedRooms?.count ?? 0
        let roomLimit = newOwnerUser.roomLimit
        
        appData.logToFile("Subscription warning check for new owner \(newOwnerUser.name) - rooms: \(roomCount)/\(roomLimit)")
        
        if roomLimit == 0 {
            return "\(newOwnerUser.name) needs a subscription to accept room ownership."
        } else if roomCount >= roomLimit {
            return "\(newOwnerUser.name) has reached their room limit of \(roomLimit). They need to upgrade their subscription."
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room Transfer Request")
                        .font(.headline)
                    Text("from \(request.initiatorUserName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Text(request.roomName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            HStack {
                Text("New owner's room usage:")
                Spacer()
                Text(subscriptionInfo)
                    .foregroundColor(canAccept ? .green : .red)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            if let warning = subscriptionWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
            
            HStack(spacing: 12) {
                Button(action: {}) {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .font(.headline)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            appData.logToFile("Decline button tapped for request \(request.id.uuidString)")
                            onDecline()
                        }
                )
                
                Button(action: {}) {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canAccept ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .font(.headline)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            appData.logToFile("Accept button tapped for request \(request.id.uuidString)")
                            onAccept()
                        }
                )
                .disabled(!canAccept)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .onAppear {
            appData.logToFile("IncomingTransferRequestRow appeared - request: \(request.id.uuidString), new owner: \(request.newOwnerId.uuidString)")
            loadRequesterUser()
            loadRecipientUser()
        }
    }
    
    private func loadRequesterUser() {
        let dbRef = Database.database().reference()
        dbRef.child("users").child(request.initiatorUserId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if let userData = snapshot.value as? [String: Any],
               let user = User(dictionary: userData) {
                DispatchQueue.main.async {
                    self.requesterUser = user
                    self.errorMessage = nil
                    if let index = self.appData.users.firstIndex(where: { $0.id == user.id }) {
                        self.appData.users[index] = user
                    } else {
                        self.appData.users.append(user)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load requester's data."
                }
            }
        }
    }
    
    private func loadRecipientUser() {
        let dbRef = Database.database().reference()
        dbRef.child("users").child(request.recipientUserId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if let userData = snapshot.value as? [String: Any],
               let user = User(dictionary: userData) {
                DispatchQueue.main.async {
                    self.recipientUser = user
                    self.errorMessage = nil
                    if let index = self.appData.users.firstIndex(where: { $0.id == user.id }) {
                        self.appData.users[index] = user
                    } else {
                        self.appData.users.append(user)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load recipient's data."
                }
            }
        }
    }
}

struct SentTransferRequestRow: View {
    let request: TransferRequest
    @ObservedObject var appData: AppData
    let onCancel: () -> Void
    let onResend: () -> Void
    @State private var toUserName: String = "Unknown User"
    
    private var statusText: String {
        switch request.status {
        case .pending:
            return "Pending Response"
        case .accepted:
            return "Accepted"
        case .acceptedPendingSubscription:
            return "Accepted - Upgrade Required"
        case .declined:
            return "Declined"
        case .expired:
            return "Expired"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    private var statusColor: Color {
        switch request.status {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .acceptedPendingSubscription:
            return .blue
        case .declined, .expired, .cancelled:
            return .red
        }
    }
    
    private var timeRemaining: String {
        if request.isExpired {
            return "Expired"
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour], from: Date(), to: request.expiresAt)
        
        if let days = components.day, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
        } else {
            return "Expires soon"
        }
    }
    
    private var isDeletable: Bool {
        return true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ownership Request")
                        .font(.headline)
                    Text("to \(toUserName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                    
                    if !request.isExpired && request.status == .pending {
                        Text(timeRemaining)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if isDeletable {
                        Text("← Swipe to delete")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .opacity(0.7)
                    }
                }
            }
            
            Text(request.roomName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            HStack(spacing: 12) {
                if request.canBeCancelled {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                
                if request.status == .declined || request.status == .expired {
                    Button("Send New Request") {
                        onResend()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .onAppear {
            loadToUserName()
        }
    }
    
    private func loadToUserName() {
        if let user = appData.users.first(where: { $0.id == request.recipientUserId }) {
            toUserName = user.name
            return
        }
        
        let dbRef = Database.database().reference()
        dbRef.child("users").child(request.recipientUserId.uuidString).child("name").observeSingleEvent(of: .value) { snapshot, _ in
            if let name = snapshot.value as? String {
                DispatchQueue.main.async {
                    self.toUserName = name
                }
            }
        }
    }
}
