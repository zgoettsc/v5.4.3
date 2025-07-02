import SwiftUI

struct AddUnitFromItemView: View {
    @ObservedObject var appData: AppData
    @Binding var selectedUnit: Unit?
    @State private var unitName: String = ""
    @Environment(\.dismiss) var dismiss
    @FocusState private var isInputActive: Bool
    
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
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Add New Unit")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Create a new measurement unit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Unit Details Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Unit Details")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 16) {
                            TextField("Unit Name", text: $unitName)
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
                    
                    // Save Button Section
                    VStack(spacing: 16) {
                        Button(action: {
                            if !unitName.isEmpty {
                                let newUnit = Unit(name: unitName)
                                appData.units.append(newUnit)
                                selectedUnit = newUnit
                                dismiss()
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                Text("Save Unit")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: unitName.isEmpty ? [.gray.opacity(0.5), .gray.opacity(0.3)] : [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: unitName.isEmpty ? .clear : .blue.opacity(0.3), radius: unitName.isEmpty ? 0 : 4, x: 0, y: 2)
                        }
                        .disabled(unitName.isEmpty)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
        }
    }
}
