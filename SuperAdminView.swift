//
//  SuperAdminView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/24/25.
//

import SwiftUI
import TelemetryDeck

struct SuperAdminView: View {
    @ObservedObject var appData: AppData
    @State private var adminCode = ""
    @State private var isValidating = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingRemoveConfirmation = false
    @Environment(\.dismiss) var dismiss
    
    // Check if user already has super admin access
    private var hasSuperAdminAccess: Bool {
        return appData.currentUser?.isSuperAdmin == true
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Developer Access")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if hasSuperAdminAccess {
                        Text("Super Admin access is currently active")
                            .font(.subheadline)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Enter developer code for unlimited access")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                if hasSuperAdminAccess {
                    // Show remove access button
                    VStack(spacing: 16) {
                        Text("Super Admin Features:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Unlimited rooms")
                            }
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Developer tools access")
                            }
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Private room access")
                            }
                        }
                        .font(.subheadline)
                        
                        Button(action: {
                            showingRemoveConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.white)
                                Text("Remove Super Admin Access")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Show activation interface
                    VStack(spacing: 16) {
                        SecureField("Developer code", text: $adminCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        
                        Button(action: validateAdminCode) {
                            HStack {
                                if isValidating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.white)
                                }
                                Text(isValidating ? "Validating..." : "Activate Admin Access")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(adminCode.isEmpty ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(adminCode.isEmpty || isValidating)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Developer Access")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
        }
        .alert("Success!", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Super Admin access activated! You now have unlimited rooms.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Remove Super Admin Access", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeSuperAdminAccess()
            }
        } message: {
            Text("Are you sure you want to remove super admin access? Your room limit will be reset to your subscription plan.")
        }
    }
    
    private func validateAdminCode() {
        isValidating = true
        
        // Send telemetry for activation attempt
        TelemetryDeck.signal("super_admin_activation_attempted")
        
        appData.validateSuperAdminCode(adminCode) { isValid, error in
            DispatchQueue.main.async {
                if isValid {
                    self.appData.applySuperAdminAccess { success, applyError in
                        DispatchQueue.main.async {
                            self.isValidating = false
                            
                            if success {
                                TelemetryDeck.signal("super_admin_activated")
                                self.showingSuccess = true
                            } else {
                                self.errorMessage = applyError ?? "Failed to activate admin access"
                                self.showingError = true
                            }
                        }
                    }
                } else {
                    self.isValidating = false
                    self.errorMessage = error ?? "Invalid admin code"
                    self.showingError = true
                }
            }
        }
    }
    
    private func removeSuperAdminAccess() {
        guard let userId = appData.currentUser?.id.uuidString else {
            errorMessage = "No user found"
            showingError = true
            return
        }
        
        // Send telemetry for removal
        TelemetryDeck.signal("super_admin_removed")
        
        appData.removeSuperAdminAccess { success, error in
            DispatchQueue.main.async {
                if success {
                    self.dismiss()
                } else {
                    self.errorMessage = error ?? "Failed to remove super admin access"
                    self.showingError = true
                }
            }
        }
    }
}

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}
