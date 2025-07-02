//
//  AccountManagementView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/5/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseDatabase
import TelemetryDeck

struct AccountManagementView: View {
    @ObservedObject var appData: AppData
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showingEditNameSheet = false
    @State private var showingEditEmailSheet = false
    @State private var editedName = ""
    @State private var editedEmail = ""
    @State private var showingDeleteAccountAlert = false
    @State private var showingAccountErrorAlert = false
    @State private var accountErrorMessage = ""
    @State private var refreshTrigger = false
    @State private var displayEmail = ""
    @State private var displayName = ""
    @FocusState private var isInputActive: Bool
    
    // Computed properties to ensure UI updates
    private var currentUserEmail: String {
        let email = appData.currentUser?.email ?? "Not set"
        print("🔍 AccountManagementView: currentUserEmail computed property returning: '\(email)'")
        return email
    }
    
    private var currentUserName: String {
        let name = appData.currentUser?.name ?? "Not set"
        print("🔍 AccountManagementView: currentUserName computed property returning: '\(name)'")
        return name
    }
    
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
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Account Management")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Manage your account information and settings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Account Information Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Account Information")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            // Name Row
                            Button(action: {
                                editedName = appData.currentUser?.name ?? ""
                                showingEditNameSheet = true
                            }) {
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Name")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text(displayName.isEmpty ? currentUserName : displayName)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(.separator), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Email Row
                            Button(action: {
                                editedEmail = appData.currentUser?.email ?? ""
                                showingEditEmailSheet = true
                            }) {
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.green.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "envelope.fill")
                                                .font(.headline)
                                                .foregroundColor(.green)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Email")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text(displayEmail.isEmpty ? currentUserEmail : displayEmail)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(.separator), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Danger Zone Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Danger Zone")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        
                        Button(action: {
                            showingDeleteAccountAlert = true
                        }) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "trash.fill")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Delete Account")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    
                                    Text("Permanently delete your account and all data")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.callout)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .id(refreshTrigger)
        .onAppear {
            updateDisplayValues()
        }
        .sheet(isPresented: $showingEditNameSheet) {
            editNameSheet
        }
        .sheet(isPresented: $showingEditEmailSheet) {
            editEmailSheet
        }
        .alert(isPresented: $showingDeleteAccountAlert) {
            Alert(
                title: Text("Delete Account"),
                message: Text("This will permanently delete your account and all your data. This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteAccount()
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingAccountErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(accountErrorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Edit Name Sheet
    private var editNameSheet: some View {
        NavigationView {
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern Header
                        VStack(spacing: 12) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Edit Your Name")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Update your display name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Name Input Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Your Name")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                TextField("Your Name", text: $editedName)
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
                                    .submitLabel(.done)
                                    .onSubmit {
                                        saveNameChanges()
                                    }
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditNameSheet = false
                    }
                    .foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveNameChanges()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            isInputActive = true
        }
    }
    
    // MARK: - Edit Email Sheet
    private var editEmailSheet: some View {
        NavigationView {
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern Header
                        VStack(spacing: 12) {
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.green, .teal]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Edit Your Email")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Update your email address")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Email Input Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Your Email")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                TextField("Email Address", text: $editedEmail)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .focused($isInputActive)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
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
                                    .submitLabel(.done)
                                    .onSubmit {
                                        saveEmailChanges()
                                    }
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Edit Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditEmailSheet = false
                    }
                    .foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEmailChanges()
                    }
                    .disabled(editedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            isInputActive = true
        }
    }
    
    // MARK: - Save Functions
    private func saveNameChanges() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let user = appData.currentUser else { return }
        
        let updatedUser = User(
            id: user.id,
            name: trimmedName,
            email: user.email,
            authId: user.authId,
            ownedRooms: user.ownedRooms,
            subscriptionPlan: user.subscriptionPlan,
            roomLimit: user.roomLimit,
            isSuperAdmin: user.isSuperAdmin,
            pendingTransferRequests: user.pendingTransferRequests,
            roomAccess: user.roomAccess,
            roomSettings: user.roomSettings,
            appVersionHistory: user.appVersionHistory
        )
        
        DispatchQueue.main.async {
            self.appData.objectWillChange.send()
            self.appData.currentUser = updatedUser
            self.refreshTrigger.toggle()
            self.appData.addUser(updatedUser)
            self.showingEditNameSheet = false
        }
    }
    
    private func saveEmailChanges() {
        let trimmedEmail = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, let user = appData.currentUser else { return }
        
        print("🔧 AccountManagementView: Saving email '\(trimmedEmail)' for user '\(user.name)'")
        print("🔧 AccountManagementView: Current user email before update: '\(user.email ?? "nil")'")
        
        let updatedUser = User(
            id: user.id,
            name: user.name,
            email: trimmedEmail,
            authId: user.authId,
            ownedRooms: user.ownedRooms,
            subscriptionPlan: user.subscriptionPlan,
            roomLimit: user.roomLimit,
            isSuperAdmin: user.isSuperAdmin,
            pendingTransferRequests: user.pendingTransferRequests,
            roomAccess: user.roomAccess,
            roomSettings: user.roomSettings,
            appVersionHistory: user.appVersionHistory
        )
        
        print("🔧 AccountManagementView: Created updated user with email: '\(updatedUser.email ?? "nil")'")
        
        DispatchQueue.main.async {
            print("🔧 AccountManagementView: About to update appData.currentUser")
            self.appData.objectWillChange.send()
            self.appData.currentUser = updatedUser
            print("🔧 AccountManagementView: Updated appData.currentUser.email to: '\(self.appData.currentUser?.email ?? "nil")'")
            
            // Update display values immediately
            self.displayEmail = trimmedEmail
            print("🔧 AccountManagementView: Set displayEmail to: '\(self.displayEmail)'")
            
            self.refreshTrigger.toggle()
            print("🔧 AccountManagementView: Toggled refreshTrigger to: \(self.refreshTrigger)")
            
            self.appData.addUser(updatedUser)
            self.showingEditEmailSheet = false
        }
    }
    
    // MARK: - Delete Account
    private func deleteAccount() {
        TelemetryDeck.signal("user.account.deleted")
        
        guard let currentUser = Auth.auth().currentUser else {
            accountErrorMessage = "No user is currently signed in."
            showingAccountErrorAlert = true
            return
        }
        
        if let appUser = appData.currentUser {
            let dbRef = Database.database().reference()
            dbRef.child("users").child(appUser.id.uuidString).removeValue { error, _ in
                if let error = error {
                    DispatchQueue.main.async {
                        self.accountErrorMessage = "Failed to delete user data: \(error.localizedDescription)"
                        self.showingAccountErrorAlert = true
                    }
                    return
                }
                
                currentUser.delete { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.accountErrorMessage = "Failed to delete account: \(error.localizedDescription)"
                            self.showingAccountErrorAlert = true
                        } else {
                            UserDefaults.standard.removeObject(forKey: "currentUserId")
                            self.appData.currentUser = nil
                            self.authViewModel.signOut()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    private func updateDisplayValues() {
        displayName = appData.currentUser?.name ?? ""
        displayEmail = appData.currentUser?.email ?? ""
        print("🔄 AccountManagementView: Updated display values - name: '\(displayName)', email: '\(displayEmail)'")
    }
}
