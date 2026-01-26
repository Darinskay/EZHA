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
        "Grams"
    }
}

struct SavedFoodSelection {
    let food: SavedFood
    let quantity: Double
}

extension SavedFood {
    func macros(for quantity: Double) -> MacroTotals {
        let per100g = resolvedPer100gMacros()
        let multiplier = quantity / 100.0
        return MacroTotals(
            calories: Int(round(per100g.calories * multiplier)),
            protein: Int(round(per100g.protein * multiplier)),
            carbs: Int(round(per100g.carbs * multiplier)),
            fat: Int(round(per100g.fat * multiplier))
        )
    }

    func macroDoubles(for quantity: Double) -> MacroDoubles {
        let per100g = resolvedPer100gMacros()
        let multiplier = quantity / 100.0
        return MacroDoubles(
            calories: per100g.calories * multiplier,
            protein: per100g.protein * multiplier,
            carbs: per100g.carbs * multiplier,
            fat: per100g.fat * multiplier
        )
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

    func resolvedPer100gMacros() -> MacroDoubles {
        if caloriesPer100g > 0 || proteinPer100g > 0 || carbsPer100g > 0 || fatPer100g > 0 {
            return MacroDoubles(
                calories: caloriesPer100g,
                protein: proteinPer100g,
                carbs: carbsPer100g,
                fat: fatPer100g
            )
        }
        guard let servingSize, servingSize > 0 else {
            return MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
        }
        let perServing = resolvedPerServingMacros()
        let multiplier = 100.0 / servingSize
        return MacroDoubles(
            calories: perServing.calories * multiplier,
            protein: perServing.protein * multiplier,
            carbs: perServing.carbs * multiplier,
            fat: perServing.fat * multiplier
        )
    }
}

struct MacroDoubles: Hashable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}
