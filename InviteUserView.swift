import SwiftUI
import MessageUI
import FirebaseDatabase
import TelemetryDeck

struct InviteUserView: View {
    @ObservedObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    @State private var phoneNumber = ""
    @State private var isAdmin = false
    @State private var invitationCode = ""
    @State private var isShowingMessageComposer = false
    @State private var isGeneratingCode = false
    @FocusState private var isInputActive: Bool
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Modern Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Invite User")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Send an invitation to join your room")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // User Information Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("User Information")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            TextField("Phone Number", text: $phoneNumber)
                                .keyboardType(.phonePad)
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
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Admin Privileges")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Gives user full access to manage the room")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isAdmin)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    // Invitation Details Section
                    if !invitationCode.isEmpty {
                        VStack(spacing: 20) {
                            HStack {
                                Text("Invitation Details")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Code Generated:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text(invitationCode)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            )
                        }
                    }
                    
                    // Info Section
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("How it works")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Text("A 6-character code will be generated and sent via SMS")
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
                    
                    // Action Button Section
                    VStack(spacing: 16) {
                        Button(action: generateAndSendInvitation) {
                            HStack {
                                if isGeneratingCode {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                        .foregroundColor(.white)
                                } else if invitationCode.isEmpty {
                                    Image(systemName: "qrcode")
                                        .font(.headline)
                                    Text("Generate Invitation Code")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                } else {
                                    Image(systemName: "message.fill")
                                        .font(.headline)
                                    Text("Send Text Message")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: (phoneNumber.isEmpty || isGeneratingCode) ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: (phoneNumber.isEmpty || isGeneratingCode) ? .clear : .blue.opacity(0.3), radius: (phoneNumber.isEmpty || isGeneratingCode) ? 0 : 4, x: 0, y: 2)
                        }
                        .disabled(phoneNumber.isEmpty || isGeneratingCode)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            // Dismiss keyboard when tapping anywhere
            isInputActive = false
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                    onComplete()
                }
            }
        }
        .sheet(isPresented: $isShowingMessageComposer) {
            MessageComposeView(
                recipients: [phoneNumber],
                body: createMessageBody(),
                isShowing: $isShowingMessageComposer,
                completion: handleMessageCompletion
            )
        }
    }
    
    func generateAndSendInvitation() {
        if invitationCode.isEmpty {
            generateInvitationCode()
        } else {
            isShowingMessageComposer = true
        }
    }
    
    // In InviteUserView.swift
    // Modify the generateInvitationCode function

    func generateInvitationCode() {
        guard let currentRoomId = UserDefaults.standard.string(forKey: "currentRoomId"),
              let currentUser = appData.currentUser else { return }
        
        isGeneratingCode = true
        TelemetryDeck.signal("invite_generated")
        
        // Generate a random 6-character alphanumeric code
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomCode = String((0..<6).map { _ in characters.randomElement()! })
        
        // Create invitation data - with explicit [String: Any] type annotation
        let invitation: [String: Any] = [
            "phoneNumber": phoneNumber,
            "isAdmin": isAdmin,
            "roomId": currentRoomId,
            "createdBy": currentUser.id.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "expiryDate": ISO8601DateFormatter().string(from: Date().addingTimeInterval(7*24*3600)), // 7 days
            "status": "created"
        ]
        
        // Get a reference to the database
        let dbRef = Database.database().reference()
        
        // Save to Firebase - use separate path to avoid affecting room data
        dbRef.child("invitations").child(randomCode).setValue(invitation) { error, _ in
            DispatchQueue.main.async {
                self.isGeneratingCode = false
                
                if error == nil {
                    self.invitationCode = randomCode
                    print("Successfully generated invitation code: \(randomCode)")
                    // DON'T call onComplete() here - this was causing the dismiss
                    // DON'T call loadFromFirebase() here either
                } else {
                    print("Error generating invitation: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }
    
    func createMessageBody() -> String {
        let appStoreLink = "https://apps.apple.com/app/tolerance-tracker/id6745797970" // Replace YOUR_APP_ID with actual ID
        return "You've been invited to use the TIPs App! Download here: \(appStoreLink) and use invitation code: \(invitationCode)"
    }
    
    func handleMessageCompletion(_ result: MessageComposeResult) {
        // Update invitation status based on message result
        let dbRef = Database.database().reference()
        
        switch result {
        case .sent:
            dbRef.child("invitations").child(invitationCode).child("status").setValue("sent") { error, _ in
                if error == nil {
                    print("Invitation status updated to 'sent'")
                }
            }
            // DON'T dismiss here - let the user stay and potentially send more invites
            onComplete()
        case .failed:
            dbRef.child("invitations").child(invitationCode).child("status").setValue("failed")
            // Don't dismiss on failure either
        case .cancelled:
            break // Do nothing, keep the invitation as is
        @unknown default:
            break
        }
        // Only dismiss if the user manually goes back
    }
}
