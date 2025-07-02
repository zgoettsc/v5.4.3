import SwiftUI

struct SubscriptionPromptView: View {
    @Binding var isPresented: Bool
    let onSubscribe: () -> Void
    let hasSubscription: Bool
    let isUpgrade: Bool
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isPresented = false
                }
            
            // Main content
            VStack(spacing: 32) {
                // Header with icon
                VStack(spacing: 16) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(isUpgrade ? "Upgrade Required" : "Subscription Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(isUpgrade ? "Upgrade your plan to create more programs" : "Create a program (room) with a subscription plan")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Free trial banner (only show for new subscriptions)
                if !isUpgrade {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "gift.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("7-Day Free Trial For New Users")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("Test before you're charged")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                // Benefits list
                VStack(spacing: 12) {
                    benefitRow(icon: "house.fill", text: "Create and manage 1-5 programs")
                    benefitRow(icon: "person.2.fill", text: "Invite care takers")
                    benefitRow(icon: "chart.line.uptrend.xyaxis", text: "Track participant progress")
                    benefitRow(icon: "icloud.fill", text: "Real-time log syncing")
                }
                .padding(.horizontal)
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        isPresented = false
                        onSubscribe()
                    }) {
                        HStack {
                            Image(systemName: "creditcard.fill")
                                .font(.headline)
                            Text(isUpgrade ? "Upgrade Subscription Plan" : "Choose Subscription Plan")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.quaternarySystemFill))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)
        }
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}
