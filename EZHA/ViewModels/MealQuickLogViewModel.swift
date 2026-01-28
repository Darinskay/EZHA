import Foundation

/// Editable ingredient with current grams text and scaling
struct EditableMealIngredient: Identifiable, Hashable {
    let id: UUID
    var name: String
    var gramsText: String
    var originalGrams: Double
    var originalCalories: Double
    var originalProtein: Double
    var originalCarbs: Double
    var originalFat: Double
    var linkedFoodId: UUID?

    var currentGrams: Double {
        parseMacro(gramsText) ?? 0
    }

    var scaledCalories: Double {
        guard originalGrams > 0, currentGrams > 0 else { return 0 }
        return originalCalories * (currentGrams / originalGrams)
    }

    var scaledProtein: Double {
        guard originalGrams > 0, currentGrams > 0 else { return 0 }
        return originalProtein * (currentGrams / originalGrams)
    }

    var scaledCarbs: Double {
        guard originalGrams > 0, currentGrams > 0 else { return 0 }
        return originalCarbs * (currentGrams / originalGrams)
    }

    var scaledFat: Double {
        guard originalGrams > 0, currentGrams > 0 else { return 0 }
        return originalFat * (currentGrams / originalGrams)
    }

    private func parseMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    init(from ingredient: SavedMealIngredient) {
        self.id = ingredient.id
        self.name = ingredient.name
        self.gramsText = Self.formatGrams(ingredient.grams)
        self.originalGrams = ingredient.grams
        self.originalCalories = ingredient.calories
        self.originalProtein = ingredient.protein
        self.originalCarbs = ingredient.carbs
        self.originalFat = ingredient.fat
        self.linkedFoodId = ingredient.linkedFoodId
    }

    init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        linkedFoodId: UUID?
    ) {
        self.id = id
        self.name = name
        self.gramsText = Self.formatGrams(grams)
        self.originalGrams = grams
        self.originalCalories = calories
        self.originalProtein = protein
        self.originalCarbs = carbs
        self.originalFat = fat
        self.linkedFoodId = linkedFoodId
    }

    private static func formatGrams(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

@MainActor
final class MealQuickLogViewModel: ObservableObject {
    @Published var editableIngredients: [EditableMealIngredient] = []
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isLibraryPickerPresented: Bool = false

    private let meal: SavedFood
    private let repository: SavedFoodRepository
    private let entryRepository: FoodEntryRepository
    private let profileRepository: ProfileRepository

    init(
        meal: SavedFood,
        repository: SavedFoodRepository = SavedFoodRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        profileRepository: ProfileRepository = ProfileRepository()
    ) {
        self.meal = meal
        self.repository = repository
        self.entryRepository = entryRepository
        self.profileRepository = profileRepository
    }

    var totals: MacroDoubles? {
        let validIngredients = editableIngredients.filter { $0.currentGrams > 0 }
        guard !validIngredients.isEmpty else { return nil }

        return validIngredients.reduce(into: MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, item in
            partial = MacroDoubles(
                calories: partial.calories + item.scaledCalories,
                protein: partial.protein + item.scaledProtein,
                carbs: partial.carbs + item.scaledCarbs,
                fat: partial.fat + item.scaledFat
            )
        }
    }

    var canSave: Bool {
        editableIngredients.contains { $0.currentGrams > 0 }
    }

    func loadIngredients() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let ingredients = try await repository.fetchMealIngredients(mealId: meal.id)
            editableIngredients = ingredients.map { EditableMealIngredient(from: $0) }
        } catch {
            errorMessage = "Unable to load ingredients: \(error.localizedDescription)"
        }
    }

    func removeIngredient(id: UUID) {
        editableIngredients.removeAll { $0.id == id }
    }

    func addLibraryIngredient(food: SavedFood, grams: Double) {
        let macros = food.macroDoubles(for: grams)
        let newIngredient = EditableMealIngredient(
            name: food.name,
            grams: grams,
            calories: macros.calories,
            protein: macros.protein,
            carbs: macros.carbs,
            fat: macros.fat,
            linkedFoodId: food.id
        )
        editableIngredients.append(newIngredient)
    }

    func saveEntry() async -> Bool {
        guard let totals = totals else {
            errorMessage = "Add at least one ingredient with grams."
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let entryId = UUID()
            let activeDate = try await resolvedActiveDate(for: userId)

            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: activeDate,
                inputType: "text",
                inputText: meal.name,
                imagePath: nil,
                calories: totals.calories,
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat,
                aiConfidence: nil,
                aiSource: "library",
                aiNotes: "Logged from saved meal",
                createdAt: nil
            )

            // Convert editable ingredients to FoodEntryItems
            let entryItems = editableIngredients.compactMap { ingredient -> FoodEntryItem? in
                guard ingredient.currentGrams > 0 else { return nil }
                return FoodEntryItem(
                    id: UUID(),
                    entryId: entryId,
                    userId: userId,
                    name: ingredient.name,
                    grams: ingredient.currentGrams,
                    calories: ingredient.scaledCalories,
                    protein: ingredient.scaledProtein,
                    carbs: ingredient.scaledCarbs,
                    fat: ingredient.scaledFat,
                    aiConfidence: nil,
                    aiNotes: "",
                    createdAt: nil
                )
            }

            try await entryRepository.insertFoodEntry(entry, items: entryItems)
            return true
        } catch {
            errorMessage = "Unable to save entry: \(error.localizedDescription)"
            return false
        }
    }

    private func resolvedActiveDate(for userId: UUID) async throws -> String {
        if let profile = try await profileRepository.fetchProfile() {
            return profile.activeDate
        }
        let dateString = Self.dateFormatter.string(from: Date())
        let defaultProfile = Profile.defaultTargets(for: userId, activeDate: dateString)
        try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)
        return dateString
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
