import SwiftUI

struct EditGroupedItemsView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    @State private var showingAddGroup = false
    @State private var editingGroup: GroupedItem?
    @State private var isEditing = false
    @State private var groupName: String = ""
    @State private var groupCategory: Category = .maintenance
    @State private var selectedItemIds: [UUID] = []
    @Binding var step: Int?
    @Environment(\.dismiss) var dismiss
    @Environment(\.isInsideNavigationView) var isInsideNavigationView

    init(appData: AppData, cycleId: UUID, step: Binding<Int?> = .constant(nil)) {
        self.appData = appData
        self.cycleId = cycleId
        self._step = step
    }

    var body: some View {
        List {
            ForEach(Category.allCases, id: \.self) { category in
                Section(header: Text(category.rawValue).foregroundColor(category.iconColor)) {
                    let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }

                    if groups.isEmpty {
                        Text("No grouped items")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(groups) { group in
                            Button(action: {
                                editingGroup = group
                                groupName = group.name
                                groupCategory = group.category
                                selectedItemIds = group.itemIds
                                showingAddGroup = true
                            }) {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundColor(category.iconColor)
                                    Text(group.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }

                    Button(action: {
                        showingAddGroup = true
                        editingGroup = nil
                        groupName = ""
                        groupCategory = category
                        selectedItemIds = []
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(category.iconColor)
                            Text("Add Grouped Item")
                                .font(.headline)
                                .foregroundColor(category.iconColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Grouped Items")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(isEditing ? "Done" : "Edit Order") {
                    isEditing.toggle()
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? EditMode.active : EditMode.inactive))
        .sheet(isPresented: $showingAddGroup) {
            NavigationStack {
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
                                Image(systemName: editingGroup == nil ? "plus.circle.fill" : "pencil.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.blue, .purple]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Text(editingGroup == nil ? "Add Grouped Item" : "Edit Grouped Item")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                
                                Text(editingGroup == nil ? "Create a new grouped item for your program" : "Modify grouped item details")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 20)
                            
                            // Group Details Section
                            VStack(spacing: 20) {
                                HStack {
                                    Text("Group Details")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                VStack(spacing: 16) {
                                    TextField("Group Name (e.g., Muffin)", text: $groupName)
                                        .textFieldStyle(PlainTextFieldStyle())
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
                                    Picker("Category", selection: $groupCategory) {
                                        ForEach(Category.allCases, id: \.self) { cat in
                                            Text(cat.rawValue).tag(cat)
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
                            
                            // Select Items Section
                            VStack(spacing: 20) {
                                HStack {
                                    Text("Select Items")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                VStack(spacing: 16) {
                                    let categoryItems = appData.cycleItems[cycleId]?.filter { $0.category == groupCategory } ?? []
                                    if categoryItems.isEmpty {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle")
                                                .font(.title2)
                                                .foregroundColor(.orange)
                                            
                                            Text("No items in this category")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 20)
                                    } else {
                                        ForEach(categoryItems) { item in
                                            Button(action: {
                                                if selectedItemIds.contains(item.id) {
                                                    selectedItemIds.removeAll { $0 == item.id }
                                                } else {
                                                    selectedItemIds.append(item.id)
                                                }
                                            }) {
                                                HStack {
                                                    Text(itemDisplayText(item: item))
                                                        .foregroundColor(.primary)
                                                        .multilineTextAlignment(.leading)
                                                    
                                                    Spacer()
                                                    
                                                    if selectedItemIds.contains(item.id) {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.headline)
                                                            .foregroundColor(.blue)
                                                    } else {
                                                        Image(systemName: "circle")
                                                            .font(.headline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(selectedItemIds.contains(item.id) ? Color.blue.opacity(0.1) : Color(.tertiarySystemBackground))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 10)
                                                                .stroke(selectedItemIds.contains(item.id) ? Color.blue : Color(.separator), lineWidth: 1)
                                                        )
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
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
                            if editingGroup != nil {
                                VStack(spacing: 20) {
                                    Button(action: {
                                        if let groupId = editingGroup?.id {
                                            appData.removeGroupedItem(groupId, fromCycleId: cycleId)
                                        }
                                        showingAddGroup = false
                                    }) {
                                        HStack {
                                            Image(systemName: "trash.fill")
                                                .font(.headline)
                                            Text("Delete Group")
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
                                }
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingAddGroup = false }) {
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
                            let newGroup = GroupedItem(
                                id: editingGroup?.id ?? UUID(),
                                name: groupName,
                                category: groupCategory,
                                itemIds: selectedItemIds
                            )
                            appData.addGroupedItem(newGroup, toCycleId: cycleId)
                            showingAddGroup = false
                        }
                        .disabled(groupName.isEmpty || selectedItemIds.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            print("EditGroupedItemsView is \(isInsideNavigationView ? "inside" : "not inside") a NavigationView")
        }
    }

    private func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        }
        return item.name
    }
}

struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
