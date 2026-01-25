import SwiftUI

struct FoodLibraryPickerView: View {
    let onSelect: (SavedFoodSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FoodLibraryViewModel()
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            List {
                if viewModel.foods.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No saved foods",
                        systemImage: "leaf",
                        description: Text("Add foods in Library to reuse them.")
                    )
                } else {
                    ForEach(filteredFoods) { food in
                        NavigationLink {
                            FoodQuantityView(food: food) { selection in
                                onSelect(selection)
                                dismiss()
                            }
                        } label: {
                            SavedFoodRow(food: food)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .task {
                await viewModel.loadFoods()
            }
        }
    }

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.foods }
        return viewModel.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct FoodQuantityView: View {
    let food: SavedFood
    let onSave: (SavedFoodSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        Form {
            Section("Food") {
                SavedFoodRow(food: food)
            }

            Section("Quantity") {
                TextField(food.unitType.quantityLabel, text: $quantityText)
                    .keyboardType(.decimalPad)
                if let label = servingLabelText {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Set Quantity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") {
                    handleSave()
                }
            }
        }
        .onAppear {
            quantityText = food.unitType == .per100g ? "100" : "1"
        }
    }

    private var servingLabelText: String? {
        guard food.unitType == .perServing else { return nil }
        if let size = food.servingSize, let unit = food.servingUnit {
            return "Serving: \(size) \(unit)"
        }
        return food.servingUnit
    }

    private func handleSave() {
        errorMessage = nil
        guard let quantity = Double(quantityText), quantity > 0 else {
            errorMessage = "Please enter a valid quantity."
            return
        }
        onSave(SavedFoodSelection(food: food, quantity: quantity))
        dismiss()
    }
}
