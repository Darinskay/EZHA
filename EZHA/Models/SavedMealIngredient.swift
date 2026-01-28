import Foundation

struct SavedMealIngredient: Identifiable, Codable, Hashable {
    var id: UUID
    var mealId: UUID
    var userId: UUID
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var linkedFoodId: UUID?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case mealId = "meal_id"
        case userId = "user_id"
        case name
        case grams
        case calories
        case protein
        case carbs
        case fat
        case linkedFoodId = "linked_food_id"
        case createdAt = "created_at"
    }

    /// Scale macros proportionally when grams change
    func scaled(to newGrams: Double) -> SavedMealIngredient {
        guard grams > 0 else { return self }
        let multiplier = newGrams / grams
        var copy = self
        copy.grams = newGrams
        copy.calories = calories * multiplier
        copy.protein = protein * multiplier
        copy.carbs = carbs * multiplier
        copy.fat = fat * multiplier
        return copy
    }
}

/// Draft for creating a new meal ingredient (before insertion)
struct SavedMealIngredientDraft: Hashable {
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var linkedFoodId: UUID?
}
