import SwiftUI

struct MissedDoseManagementView: View {
    @ObservedObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedMissedDates: Set<Date> = []
    @State private var showingConfirmation = false
    
    private var currentCycleId: UUID? {
        appData.currentCycleId()
    }
    
    private var currentCycle: Cycle? {
        guard let cycleId = currentCycleId else { return nil }
        return appData.cycles.first { $0.id == cycleId }
    }
    
    private var currentWeekDates: [Date] {
        guard let cycle = currentCycle else { return [] }
        
        let calendar = Calendar.current
        let today = Date()
        let daysSinceStart = calendar.dateComponents([.day], from: cycle.startDate, to: today).day ?? 0
        let currentWeekOffset = daysSinceStart / 7
        let weekStart = calendar.date(byAdding: .day, value: currentWeekOffset * 7, to: cycle.startDate)!
        
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekStart)
        }
    }
    
    private var treatmentItems: [Item] {
        guard let cycleId = currentCycleId else { return [] }
        return appData.getTreatmentItemsForCycle(cycleId)
    }
    
    private var existingMissedDoses: [MissedDose] {
        guard let cycleId = currentCycleId else { return [] }
        return appData.getMissedDosesForCurrentWeek(cycleId: cycleId)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Missed Treatment Doses")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Select days this week when you missed treatment food doses. This will extend your current week to make up the missed doses.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // Treatment Items Info
                    if !treatmentItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Treatment Items")
                                .font(.headline)
                            
                            ForEach(treatmentItems, id: \.id) { item in
                                HStack {
                                    Image(systemName: "pill.fill")
                                        .foregroundColor(.blue)
                                    Text(appData.itemDisplayText(item: item))
                                        .font(.body)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Currently Logged Missed Doses Section
                    if !existingMissedDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Currently Logged Missed Doses")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(existingMissedDoses, id: \.id) { missedDose in
                                    HStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                        
                                        Text(DateFormatter.weekdayFormatter.string(from: missedDose.date))
                                            .font(.body)
                                        
                                        Text("(\(DateFormatter.shortDateFormatter.string(from: missedDose.date)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Button("Remove") {
                                            removeMissedDose(missedDose.date)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Week Days Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Add New Missed Doses")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                            ForEach(currentWeekDates, id: \.self) { date in
                                DaySelectionCard(
                                    date: date,
                                    isSelected: selectedMissedDates.contains(date),
                                    isAlreadyMissed: isAlreadyMissed(date),
                                    onToggle: { toggleDate(date) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Impact Summary
                    if !selectedMissedDates.isEmpty || !existingMissedDoses.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Impact Summary")
                                .font(.headline)
                            
                            let totalMissedDays = selectedMissedDates.count + existingMissedDoses.count
                            Text("• Your current week will be extended by \(totalMissedDays) day\(totalMissedDays == 1 ? "" : "s")")
                            Text("• Treatment items will show orange X marks on missed days")
                            Text("• Next week dosing will start after completing missed doses")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Save Button
                    if !selectedMissedDates.isEmpty {
                        Button(action: {
                            showingConfirmation = true
                        }) {
                            Text("Log \(selectedMissedDates.count) Missed Dose\(selectedMissedDates.count == 1 ? "" : "s")")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Missed Doses")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Confirm Missed Doses", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Missed Doses", role: .destructive) {
                saveMissedDoses()
            }
        } message: {
            Text("This will log \(selectedMissedDates.count) missed dose\(selectedMissedDates.count == 1 ? "" : "s") and extend your current week. You can remove them later if needed.")
        }
    }
    
    private func isAlreadyMissed(_ date: Date) -> Bool {
        return existingMissedDoses.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    
    private func toggleDate(_ date: Date) {
        // Don't allow toggling dates that are already logged as missed
        if isAlreadyMissed(date) {
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        
        // Prevent future date selection
        if targetDate > today {
            return
        }
        
        if selectedMissedDates.contains(date) {
            selectedMissedDates.remove(date)
        } else {
            selectedMissedDates.insert(date)
        }
    }
    
    private func saveMissedDoses() {
        guard let cycleId = currentCycleId else { return }
        
        for date in selectedMissedDates {
            appData.addMissedDose(for: cycleId, on: date)
        }
        
        selectedMissedDates.removeAll()
    }
    
    private func removeMissedDose(_ date: Date) {
        guard let cycleId = currentCycleId else { return }
        appData.removeMissedDose(for: cycleId, on: date)
    }
}

struct DaySelectionCard: View {
    let date: Date
    let isSelected: Bool
    let isAlreadyMissed: Bool
    let onToggle: () -> Void
    
    private var dayName: String {
        DateFormatter.weekdayFormatter.string(from: date)
    }
    
    private var dayNumber: String {
        DateFormatter.dayNumberFormatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    private var isFuture: Bool {
        date > Date()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(dayName)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(dayNumber)
                .font(.title2)
                .fontWeight(.bold)
            
            if isAlreadyMissed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            } else if isSelected {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(
            Group {
                if isAlreadyMissed {
                    Color.red.opacity(0.1)
                } else if isSelected {
                    Color.orange.opacity(0.2)
                } else if isToday {
                    Color.blue.opacity(0.1)
                } else if isFuture {
                    Color.gray.opacity(0.1)
                } else {
                    Color(.systemGray6)
                }
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isAlreadyMissed ? Color.red :
                    isSelected ? Color.orange :
                    isToday ? Color.blue :
                    Color.clear,
                    lineWidth: 2
                )
        )
        .onTapGesture {
            if !isFuture && !isAlreadyMissed {
                onToggle()
            }
        }
        .opacity(isFuture ? 0.5 : 1.0)
    }
}

// MARK: - Date Formatters
extension DateFormatter {
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
