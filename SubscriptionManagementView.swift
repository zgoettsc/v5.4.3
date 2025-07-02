import SwiftUI
import RevenueCat

struct SubscriptionManagementView: View {
    @ObservedObject var appData: AppData
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedPackage: Package?
    @State private var showingPurchaseConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) var dismiss
    
    private var currentPlan: SubscriptionPlan {
        // If in grace period, show no subscription
        if appData.isInGracePeriod {
            return .none
        }
        
        if let plan = appData.currentUser?.subscriptionPlan {
            return SubscriptionPlan(productID: plan)
        }
        return .none
    }
    
    private var currentRoomCount: Int {
        return appData.currentUser?.ownedRooms?.count ?? 0
    }
    
    private var roomLimit: Int {
        // If in grace period, show 0 room limit
        if appData.isInGracePeriod {
            return 0
        }
        
        return appData.currentUser?.roomLimit ?? 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Modern Header with Gradient Background
                headerSection
                
                // Free Trial Banner
                freeTrialBanner
                
                // Current Plan Status
                currentPlanSection
                
                // Available Plans
                availablePlansSection
                
                // Action Buttons
                actionButtonsSection
                
                // Footer Links
                footerSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("Room Subscriptions")
        .navigationBarTitleDisplayMode(.large)
        
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                showError = false
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .confirmationDialog("Confirm Purchase", isPresented: $showingPurchaseConfirmation) {
            Button("Purchase") {
                if let package = selectedPackage {
                    purchasePackage(package)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let package = selectedPackage {
                Text("Purchase \(SubscriptionPlan(productID: package.storeProduct.productIdentifier).displayName) for \(package.localizedPriceString)?")
            }
        }
        .onAppear {
            storeManager.setAppData(appData)
            storeManager.loadOfferings()
            refreshUserData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SubscriptionUpdated"))) { _ in
            refreshUserData()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Choose Your Perfect Plan")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Select the number of rooms that fits your needs")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
    
    private var freeTrialBanner: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Day Free Trial")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("For first-time subscribers")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.title2)
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
    
    private var currentPlanSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Current Plan")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentPlan.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if currentPlan != .none {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill")
                                    .foregroundColor(roomUsageColor)
                                    .font(.caption)
                                
                                Text("Rooms: \(currentRoomCount)/\(roomLimit)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(roomUsageColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(roomUsageColor.opacity(0.15))
                            )
                        }
                    }
                    
                    Spacer()
                    
                    if currentPlan != .none {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)
                    }
                }
                .padding(20)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
    }
    
    private var roomUsageColor: Color {
        if roomLimit == 0 { return .gray }
        return currentRoomCount >= roomLimit ? .orange : .green
    }
    
    private var availablePlansSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Available Plans")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if storeManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading plans...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else if let packages = storeManager.offerings?.current?.availablePackages {
                LazyVStack(spacing: 16) {
                    ForEach(SubscriptionPlan.allCases.filter { $0 != .none }, id: \.self) { plan in
                        if let package = packages.first(where: { SubscriptionPlan(productID: $0.storeProduct.productIdentifier) == plan }) {
                            ModernPlanRowView(
                                plan: plan,
                                package: package,
                                isCurrentPlan: plan == currentPlan,
                                currentRoomCount: currentRoomCount,
                                isProcessing: storeManager.isLoading
                            ) {
                                selectedPackage = package
                                showingPurchaseConfirmation = true
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    Text("No subscription plans available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                storeManager.restorePurchases { success, error in
                    if !success, let error = error {
                        errorMessage = error
                        showError = true
                    }
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                    Text("Restore Purchases")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .disabled(storeManager.isLoading)
            
            Button(action: {
                storeManager.manageSubscriptions()
            }) {
                HStack {
                    Image(systemName: "gear")
                        .font(.headline)
                    Text("Manage in App Store")
                        .font(.headline)
                        .fontWeight(.medium)
                }
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
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                Button("Privacy Policy & User Agreement") {
                    if let url = URL(string: "https://www.zthreesolutions.com/privacy-policy-user-agreement") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
                
                Button("Terms of Service (EULA)") {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding(.bottom, 20)
    }
    
    private func purchasePackage(_ package: Package) {
        storeManager.purchasePackage(package, appData: appData) { success, error in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    refreshUserData()
                    dismiss()
                }
            } else if let error = error {
                errorMessage = error
                showError = true
            }
        }
    }
    
    private func refreshUserData() {
        appData.forceRefreshCurrentUser {
            // Data refreshed
        }
    }
}

// Modern Plan Row Component
struct ModernPlanRowView: View {
    let plan: SubscriptionPlan
    let package: Package
    let isCurrentPlan: Bool
    let currentRoomCount: Int
    let isProcessing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: isCurrentPlan ? {} : onTap) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(plan.displayName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if isCurrentPlan {
                                Text("CURRENT")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.green))
                            }
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("\(plan.roomLimit) Rooms")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(package.localizedPriceString)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("per month")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !isCurrentPlan {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text("7-day free trial for new subscribers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                
                if !isCurrentPlan {
                    HStack {
                        Spacer()
                        
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white)
                            }
                            
                            Text(isProcessing ? "Processing..." : "Subscribe")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isCurrentPlan ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(isCurrentPlan ? 0.1 : 0.05), radius: isCurrentPlan ? 12 : 6, x: 0, y: isCurrentPlan ? 4 : 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCurrentPlan ? .green : .clear, lineWidth: 2)
                )
        )
        .disabled(isCurrentPlan || isProcessing)
        .scaleEffect(isCurrentPlan ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCurrentPlan)
    }
}
