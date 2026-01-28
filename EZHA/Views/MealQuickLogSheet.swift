import SwiftUI

struct MealQuickLogSheet: View {
    let meal: SavedFood
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MealQuickLogViewModel

    init(meal: SavedFood, onSaved: (() -> Void)? = nil) {
        self.meal = meal
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: MealQuickLogViewModel(meal: meal))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        ingredientsCard
                        addIngredientCard
                        if let totals = viewModel.totals {
                            totalsCard(totals: totals)
                        }
                        saveButton

                        if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadIngredients()
            }
            .sheet(isPresented: $viewModel.isLibraryPickerPresented) {
                MealIngredientPickerSheet(
                    onSelect: { food, grams in
                        viewModel.addLibraryIngredient(food: food, grams: grams)
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.name)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Adjust portions for each ingredient before logging.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.headline)

            if viewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if viewModel.editableIngredients.isEmpty {
                Text("No ingredients")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach($viewModel.editableIngredients) { $ingredient in
                        IngredientRow(
                            ingredient: $ingredient,
                            onRemove: {
                                viewModel.removeIngredient(id: ingredient.id)
                            }
                        )
                    }
                }
            }
        }
        .modifier(CardModifier())
    }

    private var addIngredientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add ingredient")
                .font(.headline)

            Button {
                viewModel.isLibraryPickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    Text("Add from Library")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .modifier(CardModifier())
    }

    private func totalsCard(totals: MacroDoubles) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total")
                .font(.headline)

            HStack(spacing: 8) {
                MacroBadge(label: "Cal", value: formattedMacro(totals.calories))
                MacroBadge(label: "P", value: formattedMacro(totals.protein))
                MacroBadge(label: "C", value: formattedMacro(totals.carbs))
                MacroBadge(label: "F", value: formattedMacro(totals.fat))
            }
        }
        .modifier(CardModifier())
    }

    private var saveButton: some View {
        Button {
            Task {
                let didSave = await viewModel.saveEntry()
                if didSave {
                    dismiss()
                    onSaved?()
                    NotificationCenter.default.post(name: .foodEntrySaved, object: nil)
                    NotificationCenter.default.post(name: .switchToTodayTab, object: nil)
                }
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isSaving ? "Saving..." : "Save log")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(viewModel.canSave ? Color.indigo : Color.gray.opacity(0.4))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(!viewModel.canSave || viewModel.isSaving)
        .padding(.horizontal, 16)
    }

    private func errorCard(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedMacro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Ingredient Row

private struct IngredientRow: View {
    @Binding var ingredient: EditableMealIngredient
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 6) {
                        MacroBadge(label: "Cal", value: formattedMacro(ingredient.scaledCalories))
                        MacroBadge(label: "P", value: formattedMacro(ingredient.scaledProtein))
                        MacroBadge(label: "C", value: formattedMacro(ingredient.scaledCarbs))
                        MacroBadge(label: "F", value: formattedMacro(ingredient.scaledFat))
                    }
                }
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField("Grams", text: $ingredient.gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(width: 100)
                Text("g")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formattedMacro(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return "\(Int(value.rounded()))"
    }
}

// MARK: - Macro Badge

private struct MacroBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "--" : value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Card Modifier

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
            .padding(.horizontal, 16)
    }
}

// MARK: - Ingredient Picker Sheet

private struct MealIngredientPickerSheet: View {
    let onSelect: (SavedFood, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = IngredientPickerViewModel()
    @State private var searchText: String = ""
    @State private var selectedFood: SavedFood? = nil
    @State private var gramsText: String = "100"

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else if let food = selectedFood {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(food.name)
                                .font(.headline)

                            TextField("Grams", text: $gramsText)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            if let grams = Double(gramsText), grams > 0 {
                                let macros = food.macroDoubles(for: grams)
                                HStack(spacing: 8) {
                                    MacroBadge(label: "Cal", value: formatMacro(macros.calories))
                                    MacroBadge(label: "P", value: formatMacro(macros.protein))
                                    MacroBadge(label: "C", value: formatMacro(macros.carbs))
                                    MacroBadge(label: "F", value: formatMacro(macros.fat))
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)

                        HStack(spacing: 12) {
                            Button("Back") {
                                selectedFood = nil
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            Button("Add") {
                                if let grams = Double(gramsText), grams > 0 {
                                    onSelect(food, grams)
                                    dismiss()
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .disabled(Double(gramsText) == nil || (Double(gramsText) ?? 0) <= 0)
                        }
                        .padding(.horizontal, 16)

                        Spacer()
                    }
                    .padding(.top, 20)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(filteredFoods) { food in
                            Button {
                                selectedFood = food
                                gramsText = "100"
                            } label: {
                                SavedFoodRow(food: food)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                }
            }
            .navigationTitle(selectedFood == nil ? "Add Ingredient" : "Set Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .dismissKeyboardOnTap()
            .keyboardDoneToolbar()
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

    private func formatMacro(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return "\(Int(value.rounded()))"
    }
}

@MainActor
private final class IngredientPickerViewModel: ObservableObject {
    @Published var foods: [SavedFood] = []
    @Published var isLoading: Bool = false

    private let repository = SavedFoodRepository()

    func loadFoods() async {
        isLoading = true
        defer { isLoading = false }
        do {
            foods = try await repository.fetchNonMealFoods()
        } catch {
            foods = []
        }
    }
}
