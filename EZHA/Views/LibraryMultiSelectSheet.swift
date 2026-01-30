import SwiftUI

struct LibraryMultiSelectSheet: View {
    let onApply: ([SavedFood], [SavedMealIngredient]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FoodLibraryViewModel()
    @State private var searchText: String = ""
    @State private var selectedFoods: [UUID: SavedFood] = [:]
    @State private var mealIngredients: [UUID: [SavedMealIngredient]] = [:] // mealId -> ingredients
    @State private var loadingMealIds: Set<UUID> = []
    @FocusState private var isSearchFocused: Bool

    private let savedFoodRepository = SavedFoodRepository()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                Divider()

                // Content
                if viewModel.isLoading {
                    loadingView
                } else if filteredFoods.isEmpty {
                    emptyState
                } else {
                    foodsList
                }
            }
            .navigationTitle("Your Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .task {
                await viewModel.loadFoods()
                isSearchFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search your library...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Foods List

    private var foodsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredFoods) { food in
                    VStack(spacing: 0) {
                        LibraryFoodSelectRow(
                            food: food,
                            isSelected: isSelected(food),
                            isLoading: loadingMealIds.contains(food.id),
                            onTap: { toggleSelection(food) }
                        )

                        if food.id != filteredFoods.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !selectedFoods.isEmpty || !mealIngredients.isEmpty {
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                applySelection()
            } label: {
                Text(totalSelectedCount > 0 ? "Add \(totalSelectedCount) item\(totalSelectedCount == 1 ? "" : "s")" : "Select items")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(totalSelectedCount > 0 ? Color(red: 0.8, green: 0.2, blue: 0.6) : Color.gray.opacity(0.4))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(totalSelectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Empty / Loading States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if searchText.isEmpty {
                Image(systemName: "leaf")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No saved foods")
                    .font(.headline)
                Text("Add foods to your Library to quickly log them here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No results for \"\(searchText)\"")
                    .font(.headline)
                Text("Try a different search term.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var filteredFoods: [SavedFood] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.foods }
        return viewModel.foods.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func isSelected(_ food: SavedFood) -> Bool {
        if food.isMeal {
            return mealIngredients[food.id] != nil
        }
        return selectedFoods[food.id] != nil
    }

    private var totalSelectedCount: Int {
        let foodCount = selectedFoods.count
        let ingredientCount = mealIngredients.values.reduce(0) { $0 + $1.count }
        return foodCount + ingredientCount
    }

    private var selectionSummary: String {
        var parts: [String] = []

        if !selectedFoods.isEmpty {
            let names = selectedFoods.values.map { $0.name }
            parts.append(contentsOf: names)
        }

        for (_, ingredients) in mealIngredients {
            let names = ingredients.map { $0.name }
            parts.append(contentsOf: names)
        }

        if parts.count <= 3 {
            return "Selected: " + parts.joined(separator: ", ")
        } else {
            let first = parts.prefix(2).joined(separator: ", ")
            return "Selected: \(first) +\(parts.count - 2) more"
        }
    }

    private func toggleSelection(_ food: SavedFood) {
        if food.isMeal {
            if mealIngredients[food.id] != nil {
                // Deselect meal
                mealIngredients.removeValue(forKey: food.id)
            } else {
                // Select meal - fetch ingredients
                loadMealIngredients(food)
            }
        } else {
            if selectedFoods[food.id] != nil {
                selectedFoods.removeValue(forKey: food.id)
            } else {
                selectedFoods[food.id] = food
            }
        }
    }

    private func loadMealIngredients(_ meal: SavedFood) {
        guard !loadingMealIds.contains(meal.id) else { return }

        loadingMealIds.insert(meal.id)

        Task {
            do {
                let ingredients = try await savedFoodRepository.fetchMealIngredients(mealId: meal.id)
                mealIngredients[meal.id] = ingredients
            } catch {
                // Handle error silently or show message
            }
            loadingMealIds.remove(meal.id)
        }
    }

    private func applySelection() {
        let foods = Array(selectedFoods.values)
        let allIngredients = mealIngredients.values.flatMap { $0 }
        onApply(foods, allIngredients)
        dismiss()
    }
}

// MARK: - Library Food Select Row

private struct LibraryFoodSelectRow: View {
    let food: SavedFood
    let isSelected: Bool
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Food icon
                ZStack {
                    Circle()
                        .fill(food.isMeal ? Color.indigo.opacity(0.1) : Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: food.isMeal ? "fork.knife" : "leaf.fill")
                        .foregroundColor(food.isMeal ? .indigo : .blue)
                }

                // Food details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(food.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if food.isMeal {
                            Text("meal")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                    }

                    if food.isMeal {
                        Text("Tap to add all ingredients")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            MacroTag(value: Int(displayMacros.calories), label: "cal", color: .orange)
                            MacroTag(value: Int(displayMacros.protein), label: "P", color: .blue)
                            MacroTag(value: Int(displayMacros.carbs), label: "C", color: .green)
                            MacroTag(value: Int(displayMacros.fat), label: "F", color: .purple)
                        }

                        Text(unitLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Add/Remove button
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color(red: 0.8, green: 0.2, blue: 0.6) : Color(.secondarySystemBackground))
                            .frame(width: 32, height: 32)
                        Image(systemName: isSelected ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayMacros: MacroDoubles {
        switch food.unitType {
        case .per100g:
            return MacroDoubles(
                calories: food.caloriesPer100g,
                protein: food.proteinPer100g,
                carbs: food.carbsPer100g,
                fat: food.fatPer100g
            )
        case .perServing:
            return food.resolvedPerServingMacros()
        }
    }

    private var unitLabel: String {
        food.unitType == .per100g ? "per 100g" : "per serving"
    }
}

// MARK: - Macro Tag

private struct MacroTag: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2)
            .foregroundColor(color)
    }
}
