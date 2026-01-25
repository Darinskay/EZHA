import Foundation

struct SavedFood: Identifiable, Codable, Hashable {
    var id: UUID
    var userId: UUID
    var name: String
    var unitType: FoodUnitType
    var servingSize: Double?
    var servingUnit: String?
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case unitType = "unit_type"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case caloriesPer100g = "calories_per_100g"
        case proteinPer100g = "protein_per_100g"
        case carbsPer100g = "carbs_per_100g"
        case fatPer100g = "fat_per_100g"
        case caloriesPerServing = "calories_per_serving"
        case proteinPerServing = "protein_per_serving"
        case carbsPerServing = "carbs_per_serving"
        case fatPerServing = "fat_per_serving"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SavedFoodDraft: Hashable {
    var name: String
    var unitType: FoodUnitType
    var servingSize: Double?
    var servingUnit: String?
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double
}

enum FoodUnitType: String, CaseIterable, Identifiable, Codable {
    case per100g = "per_100g"
    case perServing = "per_serving"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .per100g:
            return "Per 100g"
        case .perServing:
            return "Per Serving"
        }
    }

    var quantityLabel: String {
        switch self {
        case .per100g:
            return "Grams"
        case .perServing:
            return "Servings"
        }
    }
}

struct SavedFoodSelection {
    let food: SavedFood
    let quantity: Double
}

extension SavedFood {
    func macros(for quantity: Double) -> MacroTotals {
        switch unitType {
        case .per100g:
            let multiplier = quantity / 100.0
            return MacroTotals(
                calories: Int(round(caloriesPer100g * multiplier)),
                protein: Int(round(proteinPer100g * multiplier)),
                carbs: Int(round(carbsPer100g * multiplier)),
                fat: Int(round(fatPer100g * multiplier))
            )
        case .perServing:
            let perServing = resolvedPerServingMacros()
            let multiplier = quantity
            return MacroTotals(
                calories: Int(round(perServing.calories * multiplier)),
                protein: Int(round(perServing.protein * multiplier)),
                carbs: Int(round(perServing.carbs * multiplier)),
                fat: Int(round(perServing.fat * multiplier))
            )
        }
    }

    func resolvedPerServingMacros() -> MacroDoubles {
        if caloriesPerServing > 0 || proteinPerServing > 0 || carbsPerServing > 0 || fatPerServing > 0 {
            return MacroDoubles(
                calories: caloriesPerServing,
                protein: proteinPerServing,
                carbs: carbsPerServing,
                fat: fatPerServing
            )
        }
        guard let servingSize, servingSize > 0 else {
            return MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
        }
        let multiplier = servingSize / 100.0
        return MacroDoubles(
            calories: caloriesPer100g * multiplier,
            protein: proteinPer100g * multiplier,
            carbs: carbsPer100g * multiplier,
            fat: fatPer100g * multiplier
        )
    }
}

struct MacroDoubles: Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}
