//
//  WeekView.swift
//  TIPsApp
//

import SwiftUI

struct WeekView: View {
    @ObservedObject var appData: AppData
    @State private var currentWeekOffset: Int = 0
    @State private var currentCycleOffset = 0
    @State private var forceRefreshID = UUID()
    
    let totalWidth = UIScreen.main.bounds.width
    let itemColumnWidth: CGFloat = 130
    
    var dynamicDayColumnWidth: CGFloat {
        let totalDays = daysInCurrentWeek()
        return (totalWidth - itemColumnWidth) / CGFloat(totalDays)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header Content (doesn't scroll)
            VStack(spacing: 16) {
                // Header Card
                headerCard()
                
                // Navigation Card
                navigationCard()
                
                // Week Header Card (this stays sticky)
                weekHeaderCard()
            }
            .padding(.top)
            .padding(.horizontal, 8)
            .background(Color(.systemGroupedBackground))
            
            // Scrollable Content
            ScrollView {
                VStack(spacing: 16) {
                    // Categories Content
                    categoriesContent()
                    
                    // Legend Card
                    legendCard()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    withAnimation {
                        if value.translation.width < -50 {
                            nextWeek()
                        } else if value.translation.width > 50 {
                            previousWeek()
                        }
                    }
                }
        )
        .onAppear {
            initializeWeekView()
            appData.globalRefresh()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.forceRefreshID = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DataRefreshed"))) { _ in
            self.forceRefreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReactionsUpdated"))) { _ in
            DispatchQueue.main.async {
                self.forceRefreshID = UUID()
            }
        }
    }
    
    // MARK: - Core Week Logic
    
    /// Get the number of days to display in the current week
    /// Base 7 days + missed doses if viewing current week
    private func daysInCurrentWeek() -> Int {
        guard let cycle = selectedCycle() else { return 7 }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        let actualCurrentWeekNumber = (daysSinceStart / 7) + 1
        let displayedWeekNumber = currentWeekOffset + 1
        
        // Only extend if we're displaying the actual current week
        if displayedWeekNumber == actualCurrentWeekNumber {
            let missedDosesThisWeek = appData.getMissedDosesForWeek(cycleId: cycle.id, weekNumber: actualCurrentWeekNumber)
            return 7 + missedDosesThisWeek.count
        } else {
            return 7
        }
    }
    
    /// Calculate the start date of the displayed week
    /// Accounts for missed doses in future weeks after current week
    private func weekStartDate() -> Date {
        guard let cycle = selectedCycle() else { return Date() }
        let calendar = Calendar.current
        
        // Calculate base week start (always starts on same day of week as cycle start)
        let baseWeekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: calendar.startOfDay(for: cycle.startDate)) ?? Date()
        
        // If this is a future week, we need to account for all missed doses from current and previous weeks
        let today = calendar.startOfDay(for: Date())
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        let actualCurrentWeekNumber = (daysSinceStart / 7) + 1
        let displayedWeekNumber = currentWeekOffset + 1
        
        if displayedWeekNumber > actualCurrentWeekNumber {
            // This is a future week - shift by cumulative missed doses
            let totalMissedDosesBeforeThisWeek = getTotalMissedDosesBeforeWeek(weekNumber: displayedWeekNumber)
            return calendar.date(byAdding: .day, value: totalMissedDosesBeforeThisWeek, to: baseWeekStart) ?? baseWeekStart
        } else {
            // Current week or past week - no shift needed
            return baseWeekStart
        }
    }
    
    /// Get total missed doses from all weeks before the specified week
    private func getTotalMissedDosesBeforeWeek(weekNumber: Int) -> Int {
        guard let cycle = selectedCycle() else { return 0 }
        
        var totalMissedDoses = 0
        for week in 1..<weekNumber {
            let missedDosesInWeek = appData.getMissedDosesForWeek(cycleId: cycle.id, weekNumber: week)
            totalMissedDoses += missedDosesInWeek.count
        }
        return totalMissedDoses
    }
    
    /// Get date for a specific day offset within the current displayed week
    private func dayDate(for offset: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate()) ?? Date()
    }
    
    /// Get weekday abbreviations for the current week
    private func weekDays() -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let totalDays = daysInCurrentWeek()
        
        return (0..<totalDays).map { offset in
            let date = dayDate(for: offset)
            return formatter.string(from: date)
        }
    }
    
    /// Check if a specific day offset represents today
    private func isTodayAtOffset(_ offset: Int) -> Bool {
        let date = dayDate(for: offset)
        return Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    /// Check if a date is the cycle start date
    private func isDateCycleStart(_ date: Date) -> Bool {
        guard let cycle = selectedCycle() else { return false }
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: cycle.startDate)
    }
    
    /// Check if a date is the cycle end date (food challenge date)
    private func isDateCycleEnd(_ date: Date) -> Bool {
        guard let cycle = selectedCycle() else { return false }
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: cycle.foodChallengeDate)
    }
    
    /// Check if there's a missed dose on a specific date
    private func hasMissedDose(on date: Date) -> Bool {
        guard let cycleId = selectedCycle()?.id else { return false }
        return appData.hasMissedDoses(for: cycleId, on: date)
    }
    
    // MARK: - Navigation
    
    private func initializeWeekView() {
        // Set to current cycle (most recent)
        currentCycleOffset = 0
        
        // Calculate current week offset within the cycle
        guard let cycle = selectedCycle() else {
            currentWeekOffset = 0
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.startOfDay(for: cycle.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: cycleStart, to: today).day ?? 0
        
        // Current week is based on days since cycle start
        currentWeekOffset = max(0, daysSinceStart / 7)
    }
    
    private func nextWeek() {
        guard let cycle = selectedCycle() else { return }
        
        let calendar = Calendar.current
        let cycleStart = calendar.startOfDay(for: cycle.startDate)
        let cycleEnd = calendar.startOfDay(for: cycle.foodChallengeDate)
        let daysBetween = calendar.dateComponents([.day], from: cycleStart, to: cycleEnd).day ?? 0
        let maxWeeksInCycle = (daysBetween / 7) + 1
        
        if currentWeekOffset < maxWeeksInCycle - 1 {
            currentWeekOffset += 1
        } else {
            // Try to move to next cycle
            if currentCycleOffset < 0 {
                currentCycleOffset += 1
                currentWeekOffset = 0
            }
        }
    }
    
    private func previousWeek() {
        if currentWeekOffset > 0 {
            currentWeekOffset -= 1
        } else {
            // Move to previous cycle if available
            if currentCycleOffset > -maxCyclesBefore() {
                currentCycleOffset -= 1
                
                // Calculate weeks in previous cycle
                if let cycle = selectedCycle() {
                    let calendar = Calendar.current
                    let cycleStartDay = calendar.startOfDay(for: cycle.startDate)
                    let cycleEndDay: Date
                    
                    if let effectiveEndDate = effectiveEndDateForCycle(cycle) {
                        cycleEndDay = calendar.date(byAdding: .day, value: -1, to: effectiveEndDate) ?? cycle.foodChallengeDate
                    } else {
                        cycleEndDay = Date()
                    }
                    
                    let days = calendar.dateComponents([.day], from: cycleStartDay, to: cycleEndDay).day ?? 0
                    let weeks = max(0, days / 7)
                    currentWeekOffset = weeks
                }
            }
        }
    }
    
    private func maxCyclesBefore() -> Int {
        return appData.cycles.count - 1
    }
    
    // MARK: - Cycle Management
    
    private func selectedCycle() -> Cycle? {
        guard !appData.cycles.isEmpty else { return nil }
        let index = max(0, min(appData.cycles.count - 1, appData.cycles.count - 1 + currentCycleOffset))
        return appData.cycles[index]
    }
    
    private func effectiveEndDateForCycle(_ cycle: Cycle) -> Date? {
        let sortedCycles = appData.cycles.sorted { $0.startDate < $1.startDate }
        if let index = sortedCycles.firstIndex(where: { $0.id == cycle.id }) {
            if index < sortedCycles.count - 1 {
                return sortedCycles[index + 1].startDate
            }
        }
        return nil
    }
    
    private func displayedCycleNumber() -> Int {
        guard !appData.cycles.isEmpty else { return 0 }
        let index = max(0, min(appData.cycles.count - 1, appData.cycles.count - 1 + currentCycleOffset))
        return appData.cycles[index].number
    }
    
    private func displayedWeekNumber() -> Int {
        return currentWeekOffset + 1
    }
    
    // MARK: - UI Components
    
    private func headerCard() -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Text("Week View")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                Text("Cycle \(displayedCycleNumber())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Text(weekRangeText())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.primary.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8) // Reduced padding to prevent cutoff
    }
    
    private func navigationCard() -> some View {
        HStack {
            Button(action: previousWeek) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Week \(displayedWeekNumber())")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: nextWeek) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.primary.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)
    }
    
    private func weekHeaderCard() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Items")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: itemColumnWidth, alignment: .leading)
                    .padding(.leading, 12)
                
                ForEach(0..<daysInCurrentWeek(), id: \.self) { offset in
                    let date = dayDate(for: offset)
                    let isToday = isTodayAtOffset(offset)
                    let isStartDate = isDateCycleStart(date)
                    let isEndDate = isDateCycleEnd(date)
                    
                    VStack(spacing: 2) {
                        if hasUnknownReaction(on: date) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        Text(weekDays()[offset])
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(isToday ? .white : .primary)
                        Text(dayNumberFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundColor(isToday ? .white : .secondary)
                    }
                    .frame(width: dynamicDayColumnWidth, height: 50)
                    .background(
                        Group {
                            if isToday {
                                Color.blue
                            } else if isStartDate {
                                Color.green.opacity(0.3)
                            } else if isEndDate {
                                Color.red.opacity(0.3)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isToday ? Color.blue :
                                isStartDate ? Color.green :
                                isEndDate ? Color.red : Color.clear,
                                lineWidth: (isStartDate || isEndDate || isToday) ? 2 : 0
                            )
                    )
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.primary.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)
    }
    
    private func categoriesContent() -> some View {
        VStack(spacing: 16) {
            ForEach(Category.allCases, id: \.self) { category in
                categoryCard(for: category)
            }
        }
    }
    
    private func categoryCard(for category: Category) -> some View {
        let items = itemsForCategory(category)
        
        return VStack(spacing: 0) {
            // Category Header
            HStack {
                Image(systemName: category.iconName)
                    .foregroundColor(category.color)
                    .frame(width: 20, height: 20)
                Text(category.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            if !items.isEmpty {
                // Items Grid
                VStack(spacing: 0) {
                    ForEach(items, id: \.id) { item in
                        itemRow(item: item, category: category)
                    }
                }
            } else {
                Text("No items in this category")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.primary.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)
    }
    
    private func itemRow(item: Item, category: Category) -> some View {
        HStack(spacing: 0) {
            // Item Name Column
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isItemComplete(item) ? .green : .primary)
                    .lineLimit(2)
                
                // Show appropriate dose information
                if category == .treatment && item.weeklyDoses != nil {
                    // For treatment items with variable doses, show week-specific dose
                    Text(getWeeklyDoseText(for: item))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let dose = item.dose, let unit = item.unit {
                    // For regular items with fixed dose
                    Text("\(formatDose(dose)) \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: itemColumnWidth, alignment: .leading)
            .padding(.leading, 12)
            
            // Day Columns
            ForEach(0..<daysInCurrentWeek(), id: \.self) { offset in
                let date = dayDate(for: offset)
                let isLogged = isItemLogged(item: item, on: date)
                let hasReactionForItem = hasReaction(for: item, on: date)
                let isMissedDose = hasMissedDose(on: date) && category == .treatment
                let isToday = isTodayAtOffset(offset)
                let isStartDate = isDateCycleStart(date)
                let isFoodChallengeDate = isDateCycleEnd(date)
                
                VStack(spacing: 2) {
                    if isMissedDose {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.bold)
                    } else if isLogged {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if hasReactionForItem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: dynamicDayColumnWidth, height: 40)
                .background(
                    // Priority: Current day > Start date > Food challenge
                    Group {
                        if isToday {
                            Color.blue.opacity(0.1)
                        } else if isStartDate {
                            Color.green.opacity(0.1)
                        } else if isFoodChallengeDate {
                            Color.red.opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                )
                .overlay(
                    // Add borders for secondary indicators
                    HStack(spacing: 0) {
                        // Left border for start date when current day
                        if isToday && isStartDate {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 3)
                        } else {
                            Spacer().frame(width: 0)
                        }
                        
                        Spacer()
                        
                        // Right border for food challenge when current day
                        if isToday && isFoodChallengeDate {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 3)
                        } else {
                            Spacer().frame(width: 0)
                        }
                    }
                )
            }
        }
        .padding(.vertical, 8)
    }
    
    private func isItemComplete(_ item: Item) -> Bool {
        guard let cycle = selectedCycle() else { return false }
        
        if item.category == .recommended {
            let weeklyCount = getWeeklyCount(for: item)
            
            // Check if it's in a group
            let isInGroup = {
                guard let cycleId = appData.currentCycleId() else { return false }
                let groups = appData.groupedItems[cycleId] ?? []
                return groups.contains { $0.itemIds.contains(item.id) }
            }()
            
            let completionThreshold: Int
            if isInGroup {
                completionThreshold = 3
            } else if item.scheduleType != nil {
                completionThreshold = appData.expectedWeeklyCount(item)
            } else {
                completionThreshold = 3
            }
            
            return weeklyCount >= completionThreshold
        }
        
        return false
    }

    private func getWeeklyCount(for item: Item) -> Int {
        guard let cycle = selectedCycle() else { return 0 }
        
        let calendar = Calendar.current
        let weekStart = weekStartDate()
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let weekEndEndOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) ?? weekEnd
        
        return appData.consumptionLog[cycle.id]?[item.id]?.filter {
            $0.date >= weekStart && $0.date <= weekEndEndOfDay
        }.count ?? 0
    }
    
    private func legendCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legend")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2), spacing: 8) {
                legendItem(symbol: "checkmark.circle.fill", color: .green, text: "Logged")
                legendItem(symbol: "exclamationmark.triangle.fill", color: .orange, text: "Reaction")
                legendItem(symbol: "xmark", color: .red, text: "Missed Dose")
                legendItem(symbol: "circle.fill", color: .gray, text: "Not Logged")
                legendItem(symbol: "play.fill", color: .green, text: "Dosing Start")
                legendItem(symbol: "flag.fill", color: .red, text: "Food Challenge")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.primary.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
    
    private func legendItem(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16, height: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get the appropriate dose text for treatment items with weekly doses
    private func getWeeklyDoseText(for item: Item) -> String {
        guard let weeklyDoses = item.weeklyDoses else {
            // Fallback to regular dose if no weekly doses
            if let dose = item.dose, let unit = item.unit {
                return "\(formatDose(dose)) \(unit)"
            }
            return ""
        }
        
        let currentDisplayedWeek = displayedWeekNumber()
        let doseKey = currentDisplayedWeek  // weeklyDoses uses 1-based indexing offset
        
        // Try to find dose for current week
        if let doseData = weeklyDoses[doseKey] {
            return "\(formatDose(doseData.dose)) \(doseData.unit) (Week \(currentDisplayedWeek))"
        }
        
        // If current week not found, find the closest smaller week
        if let availableWeeks = weeklyDoses.keys.sorted().last(where: { $0 <= doseKey }),
           let doseData = weeklyDoses[availableWeeks] {
            let displayWeek = availableWeeks
            return "\(formatDose(doseData.dose)) \(doseData.unit) (Week \(displayWeek))"
        }
        
        // If no smaller week, use the first available week
        if let firstWeek = weeklyDoses.keys.min(),
           let doseData = weeklyDoses[firstWeek] {
            let displayWeek = firstWeek 
            return "\(formatDose(doseData.dose)) \(doseData.unit) (Week \(displayWeek))"
        }
        
        // Final fallback
        if let dose = item.dose, let unit = item.unit {
            return "\(formatDose(dose)) \(unit)"
        }
        
        return ""
    }
    
    private func itemsForCategory(_ category: Category) -> [Item] {
        guard let cycle = selectedCycle() else { return [] }
        let allItems = (appData.cycleItems[cycle.id] ?? []).sorted { $0.order < $1.order }
        return allItems.filter { $0.category == category }
    }
    
    private func isItemLogged(item: Item, on date: Date) -> Bool {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        
        for (cycleId, itemsLog) in appData.consumptionLog {
            if let itemLogs = itemsLog[item.id] {
                for log in itemLogs {
                    if calendar.isDate(log.date, inSameDayAs: normalizedDate) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    private func hasReaction(for item: Item, on date: Date) -> Bool {
        guard let cycleId = appData.currentCycleId() else { return false }
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)
        let dateEnd = calendar.date(byAdding: .day, value: 1, to: dateStart)!
        
        let reactions = appData.reactions[cycleId] ?? []
        return reactions.contains { reaction in
            reaction.itemId == item.id &&
            reaction.date >= dateStart &&
            reaction.date < dateEnd
        }
    }
    
    private func hasUnknownReaction(on date: Date) -> Bool {
        guard let cycleId = appData.currentCycleId() else { return false }
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)
        let dateEnd = calendar.date(byAdding: .day, value: 1, to: dateStart)!
        
        let reactions = appData.reactions[cycleId] ?? []
        return reactions.contains { reaction in
            reaction.itemId == nil &&
            reaction.date >= dateStart &&
            reaction.date < dateEnd
        }
    }
    
    private func weekRangeText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate())
        let totalDays = daysInCurrentWeek()
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: totalDays - 1, to: weekStartDate()) ?? Date())
        let year = Calendar.current.component(.year, from: weekStartDate())
        return "\(start) - \(end), \(year)"
    }
    
    private func formatDose(_ dose: Double) -> String {
        if dose == 1.0 {
            return "1"
        } else if let fraction = Fraction.fractionForDecimal(dose) {
            return fraction.displayString
        } else if dose.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%d", Int(dose))
        }
        return String(format: "%.1f", dose)
    }
    
    private let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

// MARK: - Category Extension
extension Category {
    var iconName: String {
        switch self {
        case .medicine: return "pills.fill"
        case .maintenance: return "applelogo"
        case .treatment: return "fork.knife"
        case .recommended: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .medicine: return .blue
        case .maintenance: return .green
        case .treatment: return .purple
        case .recommended: return .orange
        }
    }
    
    var displayName: String {
        switch self {
        case .medicine: return "Medicine"
        case .maintenance: return "Maintenance"
        case .treatment: return "Treatment"
        case .recommended: return "Recommended"
        }
    }
}
