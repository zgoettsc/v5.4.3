//
//  NameInputView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 5/20/25.
//

import SwiftUI

struct NameInputView: View {
    @Binding var isPresented: Bool
    let appleSignInResult: AppleSignInResult
    let onNameSubmitted: (String, String) -> Void // Updated to include email
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var isLoading = false
    @FocusState private var isNameActive: Bool
    @FocusState private var isEmailActive: Bool
    
    var body: some View {
        NavigationView {
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
                                .font(.system(size: 80))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Welcome!")
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Please enter your information to complete setup")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // User Input Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Your Information")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                // Name Field
                                TextField("Your Name", text: $name)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .focused($isNameActive)
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
                                    .submitLabel(.next)
                                    .onSubmit {
                                        isEmailActive = true
                                    }
                                
                                // Email Field
                                TextField("Email Address", text: $email)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .focused($isEmailActive)
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
                                        submitInfo()
                                    }
                            }
                        }
                        
                        // Continue Button
                        VStack(spacing: 16) {
                            Button(action: submitInfo) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Continue")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading) ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading) ? .clear : .blue.opacity(0.3), radius: (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading) ? 0 : 4, x: 0, y: 2)
                            }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
                isNameActive = false
                isEmailActive = false
            }
        }
        .onAppear {
            // Pre-fill with Apple provided name if available
            if let displayName = appleSignInResult.displayName, !displayName.isEmpty {
                name = displayName
            }
        }
    }
    
    private func submitInfo() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty && !trimmedEmail.isEmpty else { return }
        
        isLoading = true
        onNameSubmitted(trimmedName, trimmedEmail)
    }
}
