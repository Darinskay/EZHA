import Foundation

enum SuggestionMealType: String, CaseIterable, Identifiable {
    case meal = "Meal"
    case snack = "Snack"

    var id: String { rawValue }
}

struct MealSuggestion: Identifiable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let warning: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        warning: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.warning = warning
        self.notes = notes
    }
}
