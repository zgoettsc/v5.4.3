import SwiftUI
import AVKit

struct OnboardingView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var isShowingOnboarding: Bool
    @State private var currentPage = 0
    @State private var players: [Int: AVPlayer] = [:]
    @State private var isVideoFullScreen = false
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Understanding Cycles",
            content: "",
            imageName: "cycle-graphic",
            isVideo: false
        ),
        OnboardingPage(
            title: "Subscription & Rooms",
            content: "Choose your plan and manage multiple participants with ease",
            imageName: "subscription-rooms-video",
            isVideo: true,
            features: [
                FeatureItem(icon: "person.2.fill", title: "1-5 Room Levels", description: "Based on participant needs"),
                FeatureItem(icon: "key.fill", title: "Free Room Joining!", description: "Via invite codes from an existing user"),
                FeatureItem(icon: "switch.2", title: "Easy Switching", description: "Between rooms in Settings"),
                FeatureItem(icon: "person.badge.plus", title: "Invite Others", description: "Caregivers, family, clinicians")
            ]
        ),
        OnboardingPage(
            title: "Cycle Setup",
            content: "Configure your treatment plan with precision and flexibility",
            imageName: "cycle-setup-video",
            isVideo: true,
            features: [
                FeatureItem(icon: "calendar.badge.plus", title: "Setup Process", description: "Input dosing dates and food challenges"),
                FeatureItem(icon: "square.stack.3d.up.fill", title: "Items and Groups", description: "Organize by category with dose reminders"),
                FeatureItem(icon: "gear", title: "Admin Controls", description: "Modify plans through Settings"),
                FeatureItem(icon: "arrow.clockwise", title: "Auto Sync", description: "Logs sync to all users")
            ]
        ),
        OnboardingPage(
            title: "Home Screen",
            content: "Your central hub for logging and monitoring treatment progress",
            imageName: "home-screen-video",
            isVideo: true,
            features: [
                FeatureItem(icon: "house.fill", title: "Daily Logging", description: "Log items and view active timers"),
                FeatureItem(icon: "timer", title: "Treatment Timers", description: "Appear after logging treatment items"),
                FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Progress Tracking", description: "3-5x weekly goals for recommended foods")
            ]
        ),
        OnboardingPage(
            title: "Navigation Tabs",
            content: "Comprehensive views for tracking and managing your treatment journey",
            imageName: "tabs-video",
            isVideo: true,
            features: [
                FeatureItem(icon: "calendar", title: "Week View", description: "Calendar format with visual indicators"),
                FeatureItem(icon: "exclamationmark.triangle.fill", title: "Reactions", description: "Log symptoms and treatment details"),
                FeatureItem(icon: "clock.fill", title: "History", description: "Chronological record with filters"),
                FeatureItem(icon: "gear", title: "Settings", description: "Personalize your experience")
            ]
        ),
        OnboardingPage(
            title: "Settings & Control",
            content: "Manage your experience with powerful administrative tools",
            imageName: "settings-video",
            isVideo: true,
            features: [
                FeatureItem(icon: "pencil.circle.fill", title: "Edit Plan", description: "Modify cycles, items, groups, and units"),
                FeatureItem(icon: "bell.fill", title: "Notifications", description: "Dose reminders and treatment timer alerts"),
                FeatureItem(icon: "building.2.fill", title: "Room Management", description: "Switch between rooms to track multiple participants"),
                FeatureItem(icon: "person.2.badge.plus", title: "User Invites", description: "Share access with care givers and your care team")
            ]
        )
    ]
    
    init(isShowingOnboarding: Binding<Bool>) {
        self._isShowingOnboarding = isShowingOnboarding
        var initialPlayers: [Int: AVPlayer] = [:]
        for (index, page) in pages.enumerated() where page.isVideo {
            if let videoURL = Bundle.main.url(forResource: page.imageName, withExtension: "mp4") {
                let player = AVPlayer(url: videoURL)
                initialPlayers[index] = player
            }
        }
        self._players = State(initialValue: initialPlayers)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Modern gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Compact header
                    headerView
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    
                    // Main content
                    TabView(selection: $currentPage) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            pageContentView(for: index, geometry: geometry)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
                    
                    // Bottom section with indicators and skip
                    bottomSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            setupInitialVideo()
        }
        .onChange(of: currentPage) { newPage in
            handlePageChange(newPage)
        }
        .onDisappear {
            cleanupPlayers()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            // Back button
            if currentPage > 0 {
                Button(action: { withAnimation { currentPage -= 1 } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.primary)
                }
            } else {
                Spacer().frame(width: 60)
            }
            
            Spacer()
            
            // Next/Get Started button
            if currentPage < pages.count - 1 {
                Button(action: { withAnimation { currentPage += 1 } }) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
            } else {
                Button(action: completeOnboarding) {
                    Text("Get Started")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.blue)
                        )
                }
            }
        }
    }
    
    // MARK: - Page Content View
    private func pageContentView(for index: Int, geometry: GeometryProxy) -> some View {
        let page = pages[index]
        
        return VStack(spacing: 0) {
            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            // Subtitle
            if !page.content.isEmpty {
                Text(page.content)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            
            if index == 0 {
                // First page with graphic and definitions
                firstPageContent(geometry: geometry)
            } else {
                // Video pages
                videoPageContent(for: index, geometry: geometry)
            }
        }
    }
    
    // MARK: - First Page Content
    private func firstPageContent(geometry: GeometryProxy) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Graphic
                if let image = UIImage(named: "cycle-graphic") {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: geometry.size.height * 0.35)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray5))
                        .frame(height: geometry.size.height * 0.35)
                        .overlay(Text("Graphic not found").foregroundColor(.red))
                        .padding(.horizontal, 20)
                }
                
                // Definition cards
                VStack(spacing: 16) {
                    ForEach(cycleDefinitions, id: \.term) { definition in
                        DefinitionCard(term: definition.term, description: definition.description)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Video Page Content
    private func videoPageContent(for index: Int, geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Large video player
            if let player = players[index] {
                VideoPlayer(player: player)
                    .frame(height: geometry.size.height * 0.4)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 20)
                    .onTapGesture {
                        // Could add full-screen functionality here
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(height: geometry.size.height * 0.4)
                    .overlay(Text("Video not found").foregroundColor(.red))
                    .padding(.horizontal, 20)
            }
            
            // Feature cards
            if let features = pages[index].features {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(features, id: \.title) { feature in
                            FeatureCard(feature: feature)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - Bottom Section
    private var bottomSection: some View {
        VStack(spacing: 16) {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            
            // Skip button
            if currentPage < pages.count - 1 {
                Button(action: completeOnboarding) {
                    Text("Skip Tutorial")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func setupInitialVideo() {
        if currentPage > 0, let player = players[currentPage] {
            player.seek(to: .zero)
            player.play()
        }
    }
    
    private func handlePageChange(_ newPage: Int) {
        players.forEach { $0.value.pause() }
        
        if newPage > 0, let player = players[newPage] {
            player.seek(to: .zero)
            player.play()
        }
    }
    
    private func cleanupPlayers() {
        players.forEach { $0.value.pause() }
        players.removeAll()
    }
    
    private func completeOnboarding() {
        isShowingOnboarding = false
        // Remove this line: UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        presentationMode.wrappedValue.dismiss()
    }
    
    // MARK: - Data
    private let cycleDefinitions = [
        CycleDefinition(term: "Room", description: "The place for all things related to an individual participant. Contains all cycle data for a single participant."),
        CycleDefinition(term: "Cycle", description: "The current round of treatment foods the participant is working on."),
        CycleDefinition(term: "Cycle Number", description: "What round of treatment foods the participant is working on. Example: Launch visit → visit 1 = cycle 1."),
        CycleDefinition(term: "Dosing Start Date", description: "The first day the treatment foods were dosed in the cycle."),
        CycleDefinition(term: "Food Challenge Date", description: "The date the cycle treatment foods will be challenged.")
    ]
}

// MARK: - Supporting Views
struct FeatureCard: View {
    let feature: FeatureItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: feature.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                
                Spacer()
            }
            
            Text(feature.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(feature.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct DefinitionCard: View {
    let term: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(term)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Data Models
struct OnboardingPage {
    let title: String
    let content: String
    let imageName: String
    let isVideo: Bool
    let features: [FeatureItem]?
    
    init(title: String, content: String, imageName: String, isVideo: Bool, features: [FeatureItem]? = nil) {
        self.title = title
        self.content = content
        self.imageName = imageName
        self.isVideo = isVideo
        self.features = features
    }
}

struct FeatureItem {
    let icon: String
    let title: String
    let description: String
}

struct CycleDefinition {
    let term: String
    let description: String
}

struct OnboardingTutorialButton: View {
    @Binding var isShowingOnboarding: Bool
    
    var body: some View {
        Button(action: {
            isShowingOnboarding = true
        }) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("View Tutorial")
                    .font(.headline)
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isShowingOnboarding: .constant(true))
    }
}
