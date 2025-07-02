import SwiftUI

struct ItemFormView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    let initialCategory: Category?
    let editingItem: Item?
    
    @State private var itemName: String = ""
    @State private var dose: String = ""
    @State private var selectedUnit: Unit?
    @State private var selectedCategory: Category
    @State private var inputMode: InputMode = .decimal
    @State private var selectedFraction: Fraction?
    @State private var addFutureDoses: Bool = false
    @State private var weeklyDoses: [Int: (dose: String, unit: Unit?, fraction: Fraction?, inputMode: InputMode)] = [:]
    @State private var showingDeleteConfirmation = false
    
    // New scheduling state variables
    @State private var enableAdvancedScheduling: Bool = false
    @State private var scheduleType: ScheduleType = .everyday
    @State private var customScheduleDays: Set<Int> = []
    @State private var everyOtherDayStartDate: Date = Date()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.isInsideNavigationView) var isInsideNavigationView
    @FocusState private var isInputActive: Bool
    
    enum InputMode: String, CaseIterable {
        case decimal = "Decimal"
        case fraction = "Fraction"
    }
    
    init(appData: AppData, cycleId: UUID, initialCategory: Category? = nil, editingItem: Item? = nil) {
        self.appData = appData
        self.cycleId = cycleId
        self.initialCategory = initialCategory
        self.editingItem = editingItem
        
        print("ItemFormView initialized with initialCategory: \(initialCategory?.rawValue ?? "nil"), editingItem: \(editingItem != nil ? editingItem!.name : "none")")
        
        if let item = editingItem {
            self._itemName = State(initialValue: item.name)
            self._selectedCategory = State(initialValue: item.category)
            self._dose = State(initialValue: item.dose.map { String($0) } ?? "")
            
            // Load existing scheduling settings
            self._enableAdvancedScheduling = State(initialValue: item.scheduleType != nil)
            self._scheduleType = State(initialValue: item.scheduleType ?? .everyday)
            self._customScheduleDays = State(initialValue: item.customScheduleDays ?? [])
            self._everyOtherDayStartDate = State(initialValue: item.everyOtherDayStartDate ?? Date())
            
            if let unitName = item.unit, !unitName.isEmpty {
                if let existingUnit = appData.units.first(where: { $0.name == unitName }) {
                    self._selectedUnit = State(initialValue: existingUnit)
                } else {
                    let newUnit = Unit(name: unitName)
                    appData.addUnit(newUnit)
                    self._selectedUnit = State(initialValue: newUnit)
                }
            } else {
                self._selectedUnit = State(initialValue: nil)
            }
            
            self._addFutureDoses = State(initialValue: item.weeklyDoses != nil)
            
            if let dose = item.dose, let fraction = Fraction.fractionForDecimal(dose) {
                self._inputMode = State(initialValue: .fraction)
                self._selectedFraction = State(initialValue: fraction)
            } else {
                self._inputMode = State(initialValue: .decimal)
                self._selectedFraction = State(initialValue: nil)
            }
            
            if let weeklyDoses = item.weeklyDoses {
                var processedWeeklyDoses: [Int: (dose: String, unit: Unit?, fraction: Fraction?, inputMode: InputMode)] = [:]
                for (week, doseData) in weeklyDoses {
                    let unit: Unit?
                    let unitName = doseData.unit
                    if !unitName.isEmpty {
                        if let existingUnit = appData.units.first(where: { $0.name == unitName }) {
                            unit = existingUnit
                        } else {
                            let newUnit = Unit(name: unitName)
                            appData.addUnit(newUnit)
                            unit = newUnit
                        }
                    } else {
                        unit = nil
                    }
                    
                    let fraction = Fraction.fractionForDecimal(doseData.dose)
                    let inputMode: InputMode = fraction != nil ? .fraction : .decimal
                    
                    processedWeeklyDoses[week] = (
                        dose: String(doseData.dose),
                        unit: unit,
                        fraction: fraction,
                        inputMode: inputMode
                    )
                }
                self._weeklyDoses = State(initialValue: processedWeeklyDoses)
                print("Loaded weeklyDoses for editing: \(processedWeeklyDoses)")
            } else {
                self._weeklyDoses = State(initialValue: [:])
            }
            print("Editing item, selectedCategory set to: \(item.category.rawValue)")
        } else {
            let defaultCategory = initialCategory ?? .maintenance
            self._itemName = State(initialValue: "")
            self._selectedCategory = State(initialValue: defaultCategory)
            self._dose = State(initialValue: "")
            self._selectedUnit = State(initialValue: nil)
            self._selectedFraction = State(initialValue: nil)
            self._weeklyDoses = State(initialValue: [:])
            self._addFutureDoses = State(initialValue: false)
            print("New item, selectedCategory set to: \(defaultCategory.rawValue)")
        }
    }
    
    private var currentWeek: Int {
        guard let cycle = appData.cycles.first(where: { $0.id == cycleId }) else { return 1 }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: cycle.startDate, to: Date()).day ?? 0
        return (daysSinceStart / 7) + 1
    }
    
    private var totalWeeks: Int {
        guard let cycle = appData.cycles.first(where: { $0.id == cycleId }) else { return 12 }
        let calendar = Calendar.current
        guard let lastDosingDay = calendar.date(byAdding: .day, value: -1, to: cycle.foodChallengeDate) else { return 12 }
        let days = calendar.dateComponents([.day], from: cycle.startDate, to: lastDosingDay).day ?? 83
        return (days / 7) + 1
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                VStack(spacing: 12) {
                    Text(editingItem == nil ? "Add New Item" : "Edit Item")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text(editingItem == nil ? "Create a new item for your program" : "Modify item details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Item Details Section
                VStack(spacing: 20) {
                    HStack {
                        Text("Item Details")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        TextField("Item Name", text: $itemName)
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
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    )
                }
                
                // Category Section
                VStack(spacing: 20) {
                    HStack {
                        Text("Category")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(Category.allCases, id: \.self) { category in
                                Text(category.rawValue)
                                    .tag(category)
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                        )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    )
                }
                
                // Replace the existing dose toggle section in ItemFormView with this:

                VStack(spacing: 20) {
                    HStack {
                        Text("Dosing Method")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        // New toggle layout with labels on both sides
                        HStack {
                            Text("Constant")
                                .font(.body)
                                .fontWeight(addFutureDoses ? .regular : .semibold)
                                .foregroundColor(addFutureDoses ? .secondary : .primary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $addFutureDoses)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .onChange(of: addFutureDoses) { newValue in
                                    weeklyDoses = [:]
                                }
                            
                            Spacer()
                            
                            Text("Week by Week")
                                .font(.body)
                                .fontWeight(addFutureDoses ? .semibold : .regular)
                                .foregroundColor(addFutureDoses ? .primary : .secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if addFutureDoses {
                                Text("Weekly doses: Set different dose amounts for each week of the treatment cycle. Perfect for treatments that increase or decrease doses over time.")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Constant dose: Use the same dose amount for each week throughout the treatment cycle.")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    )
                }
                
                
                // Dose Input Sections
                if addFutureDoses {
                    // Weekly Doses Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Weekly Doses")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            ForEach(currentWeek...totalWeeks, id: \.self) { week in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Week \(week)")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    
                                    weeklyDoseContent(week: week)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.quaternarySystemFill))
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                } else {
                    // Input Mode Section (for constant dose)
                    VStack(spacing: 20) {
                        HStack {
                            Text("Input Mode")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            Picker("Input Mode", selection: $inputMode) {
                                ForEach(InputMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    // Dose Section (for constant dose)
                    VStack(spacing: 20) {
                        HStack {
                            Text("Dose")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            dosageInputContent()
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                }
                
                // Advanced Scheduling Section
                VStack(spacing: 20) {
                    HStack {
                        Text("Advanced Scheduling")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    
                    VStack(spacing: 16) {
                        Toggle("Enable Custom Schedule", isOn: $enableAdvancedScheduling)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .onChange(of: enableAdvancedScheduling) { newValue in
                                if !newValue {
                                    scheduleType = .everyday
                                    customScheduleDays = []
                                }
                            }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Customize when this item appears during the week. Examples: every other day, weekdays only, or specific days like Monday/Wednesday/Friday.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if enableAdvancedScheduling {
                            VStack(spacing: 16) {
                                Picker("Schedule Type", selection: $scheduleType) {
                                    ForEach(ScheduleType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                
                                // Schedule type descriptions
                                VStack(alignment: .leading, spacing: 8) {
                                    switch scheduleType {
                                    case .everyday:
                                        Text("Item appears every day")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    case .everyOtherDay:
                                        Text("Item appears every other day based on cycle start date")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    case .custom:
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Select which days the item should appear:")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            customDayPicker()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    )
                }
                
                // Delete Section (for editing)
                if editingItem != nil {
                    VStack(spacing: 20) {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .font(.headline)
                                Text("Delete Item")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.red.opacity(0.8), .red.opacity(0.6)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .alert("Delete \(itemName)?", isPresented: $showingDeleteConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                if let itemId = editingItem?.id {
                                    appData.removeItem(itemId, fromCycleId: cycleId)
                                }
                                dismiss()
                            }
                        } message: {
                            Text("This action cannot be undone.")
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
                Button("Save") {
                    saveItem()
                }
                .disabled(!isValid())
            }
        }
    }
    
    // New function for custom day picker
    private func customDayPicker() -> some View {
        HStack(spacing: 8) {
            let dayNames = ["S", "M", "T", "W", "T", "F", "S"]
            let dayValues = [1, 2, 3, 4, 5, 6, 7] // iOS weekday format: 1=Sunday, 2=Monday, etc.
            
            ForEach(0..<7, id: \.self) { index in
                Button(action: {
                    let dayValue = dayValues[index]
                    if customScheduleDays.contains(dayValue) {
                        customScheduleDays.remove(dayValue)
                    } else {
                        customScheduleDays.insert(dayValue)
                    }
                }) {
                    Text(dayNames[index])
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(customScheduleDays.contains(dayValues[index]) ? .blue : Color(.tertiarySystemBackground))
                        )
                        .foregroundColor(customScheduleDays.contains(dayValues[index]) ? .white : .primary)
                        .overlay(
                            Circle()
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private func dosageInputContent() -> some View {
        VStack(spacing: 16) {
            if inputMode == .decimal {
                HStack(spacing: 12) {
                    TextField("Dose", text: $dose)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($isInputActive)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.tertiarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                        )
                    
                    Picker("Unit", selection: $selectedUnit) {
                        Text("Select Unit").tag(nil as Unit?)
                        ForEach(appData.units) { unit in
                            Text(unit.name).tag(Unit?.some(unit))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                }
            } else {
                HStack(spacing: 12) {
                    Picker("Dose", selection: $selectedFraction) {
                        Text("Select fraction").tag(nil as Fraction?)
                        ForEach(Fraction.commonFractions) { fraction in
                            Text(fraction.displayString).tag(fraction as Fraction?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                    
                    Picker("Unit", selection: $selectedUnit) {
                        Text("Select Unit").tag(nil as Unit?)
                        ForEach(appData.units) { unit in
                            Text(unit.name).tag(Unit?.some(unit))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                }
            }
            
            NavigationLink(destination: AddUnitFromItemView(appData: appData, selectedUnit: $selectedUnit)) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.callout)
                    Text("Add a New Unit")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.quaternarySystemFill))
                .foregroundColor(.blue)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
        }
    }
    
    private func weeklyDoseContent(week: Int) -> some View {
        VStack(spacing: 16) {
            // Input mode picker specific to this week
            Picker("Input Mode", selection: Binding(
                get: { weeklyDoses[week]?.inputMode ?? .decimal },
                set: { newMode in
                    var weekData = weeklyDoses[week, default: ("", nil, nil, .decimal)]
                    weekData.inputMode = newMode
                    weeklyDoses[week] = weekData
                }
            )) {
                ForEach(InputMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Show appropriate input type based on the week's input mode
            if weeklyDoses[week]?.inputMode ?? .decimal == .decimal {
                HStack(spacing: 12) {
                    TextField("Dose", text: Binding(
                        get: { weeklyDoses[week]?.dose ?? "" },
                        set: { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            weeklyDoses[week, default: ("", nil, nil, .decimal)].dose = filtered
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isInputActive)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                    
                    Picker("Unit", selection: Binding(
                        get: { weeklyDoses[week]?.unit },
                        set: { weeklyDoses[week, default: ("", nil, nil, .decimal)].unit = $0 }
                    )) {
                        Text("Select Unit").tag(Unit?.none)
                        ForEach(appData.units) { unit in
                            Text(unit.name).tag(Unit?.some(unit))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                }
            } else {
                HStack(spacing: 12) {
                    Picker("Dose", selection: Binding(
                        get: { weeklyDoses[week]?.fraction },
                        set: { weeklyDoses[week, default: ("", nil, nil, .fraction)].fraction = $0 }
                    )) {
                        Text("Select fraction").tag(nil as Fraction?)
                        ForEach(Fraction.commonFractions) { fraction in
                            Text(fraction.displayString).tag(fraction as Fraction?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                    
                    Picker("Unit", selection: Binding(
                        get: { weeklyDoses[week]?.unit },
                        set: { weeklyDoses[week, default: ("", nil, nil, .fraction)].unit = $0 }
                    )) {
                        Text("Select Unit").tag(Unit?.none)
                        ForEach(appData.units) { unit in
                            Text(unit.name).tag(Unit?.some(unit))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                }
            }
            
            NavigationLink(destination: AddUnitFromItemView(appData: appData, selectedUnit: Binding(
                get: { weeklyDoses[week]?.unit },
                set: { weeklyDoses[week, default: ("", nil, nil, .decimal)].unit = $0 }
            ))) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.callout)
                    Text("Add a Unit")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.quaternarySystemFill))
                .foregroundColor(.blue)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
        }
    }
    
    private func isValid() -> Bool {
        if itemName.isEmpty { return false }
        
        // Validate custom schedule if enabled
        if enableAdvancedScheduling && scheduleType == .custom && customScheduleDays.isEmpty {
            return false
        }
        
        if addFutureDoses {
            return weeklyDoses.contains { weekData in
                let doseValid = weekData.value.inputMode == .decimal ?
                (!weekData.value.dose.isEmpty && Double(weekData.value.dose) != nil) :
                (weekData.value.fraction != nil)
                return doseValid && weekData.value.unit != nil
            }
        } else {
            return (inputMode == .decimal && !dose.isEmpty && Double(dose) != nil) ||
            (inputMode == .fraction && selectedFraction != nil) &&
            selectedUnit != nil
        }
    }
    
    func saveItem() {
        guard !itemName.isEmpty else { return }
        
        // Add scheduling properties to newItem
        let finalScheduleType = enableAdvancedScheduling ? scheduleType : nil
        let finalCustomScheduleDays = (scheduleType == .custom && enableAdvancedScheduling) ? customScheduleDays : nil
        let finalEveryOtherDayStartDate = (scheduleType == .everyOtherDay && enableAdvancedScheduling) ? everyOtherDayStartDate : nil
        
        let newItem: Item  // Declare as let, not var
        
        if addFutureDoses {
            var weeklyDosesData: [Int: WeeklyDoseData] = [:]
            
            for (week, value) in weeklyDoses {
                let doseValue: Double?
                if value.inputMode == .decimal {
                    doseValue = Double(value.dose)
                } else {
                    doseValue = value.fraction?.decimalValue
                }
                
                if let validDose = doseValue, let unit = value.unit {
                    weeklyDosesData[week] = WeeklyDoseData(dose: validDose, unit: unit.name)
                }
            }
            
            guard !weeklyDosesData.isEmpty else {
                print("Error: No valid weekly doses provided")
                return
            }
            
            // Get first valid unit for item.unit field
            let firstUnit = weeklyDosesData.values.first?.unit
            
            newItem = Item(
                id: editingItem?.id ?? UUID(),
                name: itemName,
                category: selectedCategory,
                dose: nil,
                unit: firstUnit,
                weeklyDoses: weeklyDosesData,
                order: editingItem?.order ?? 0,
                scheduleType: finalScheduleType,
                customScheduleDays: finalCustomScheduleDays,
                everyOtherDayStartDate: finalEveryOtherDayStartDate
            )
        } else {
            guard let doseValue = inputMode == .decimal ? Double(dose) : selectedFraction?.decimalValue,
                  let unit = selectedUnit else { return }
            
            newItem = Item(
                id: editingItem?.id ?? UUID(),
                name: itemName,
                category: selectedCategory,
                dose: doseValue,
                unit: unit.name,
                weeklyDoses: nil,
                order: editingItem?.order ?? 0,
                scheduleType: finalScheduleType,
                customScheduleDays: finalCustomScheduleDays,
                everyOtherDayStartDate: finalEveryOtherDayStartDate
            )
        }
        
        print("Saving item: \(newItem.name), category: \(newItem.category.rawValue), weeklyDoses: \(String(describing: newItem.weeklyDoses))")
        print("Scheduling settings: enabled: \(enableAdvancedScheduling), type: \(scheduleType), customDays: \(customScheduleDays)")
        
        appData.addItem(newItem, toCycleId: cycleId) { success in
            if success {
                DispatchQueue.main.async {
                    dismiss()
                }
            } else {
                print("Failed to save item: \(newItem.name)")
            }
        }
    }
}
