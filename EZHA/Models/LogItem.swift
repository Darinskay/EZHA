import Foundation

/// Represents a single item in the unified log sheet
struct LogItem: Identifiable {
    let id: UUID
    var name: String
    var gramsText: String
    var source: LogItemSource

    // For library/meal items - reference to calculate macros dynamically
    var savedFood: SavedFood?

    // For AI items - fixed macros from analysis (per the analyzed grams)
    var aiMacros: MacroDoubles?
    var aiOriginalGrams: Double?
    var aiSource: String?

    /// Initialize from a library food selection
    init(from food: SavedFood, grams: Double = 100) {
        self.id = UUID()
        self.name = food.name
        self.gramsText = LogItem.formatGrams(grams)
        self.source = .library
        self.savedFood = food
        self.aiMacros = nil
        self.aiOriginalGrams = nil
        self.aiSource = nil
    }

    /// Initialize from a meal ingredient
    init(from ingredient: SavedMealIngredient) {
        self.id = UUID()
        self.name = ingredient.name
        self.gramsText = LogItem.formatGrams(ingredient.grams)
        self.source = .meal
        self.savedFood = nil
        // Store the macros per the original grams for scaling
        self.aiMacros = MacroDoubles(
            calories: ingredient.calories,
            protein: ingredient.protein,
            carbs: ingredient.carbs,
            fat: ingredient.fat
        )
        self.aiOriginalGrams = ingredient.grams
        self.aiSource = nil
    }

    /// Initialize from an AI-analyzed item
    init(from aiItem: MacroItemEstimate, source: String? = nil) {
        self.id = UUID()
        self.name = aiItem.name
        self.gramsText = LogItem.formatGrams(aiItem.grams)
        self.source = .ai
        self.savedFood = nil
        self.aiMacros = MacroDoubles(
            calories: aiItem.calories,
            protein: aiItem.protein,
            carbs: aiItem.carbs,
            fat: aiItem.fat
        )
        self.aiOriginalGrams = aiItem.grams
        self.aiSource = source
    }

    /// Parsed grams value from gramsText
    var grams: Double {
        Double(gramsText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Calculate current macros based on grams
    var macros: MacroDoubles {
        if let food = savedFood {
            // Library food - calculate from per100g
            return food.macroDoubles(for: grams)
        } else if let aiMacros, let originalGrams = aiOriginalGrams, originalGrams > 0 {
            // AI or meal item - scale from original
            let multiplier = grams / originalGrams
            return MacroDoubles(
                calories: aiMacros.calories * multiplier,
                protein: aiMacros.protein * multiplier,
                carbs: aiMacros.carbs * multiplier,
                fat: aiMacros.fat * multiplier
            )
        }
        return MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
    }

    private static func formatGrams(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

enum LogItemSource: String {
    case library
    case ai
    case meal

    var label: String {
        switch self {
        case .library: return "Library"
        case .ai: return "AI"
        case .meal: return "Meal"
        }
    }
}

/// Selection state for multi-select library picker
struct LibrarySelection: Identifiable {
    let id: UUID
    let food: SavedFood
    var isExpanded: Bool = false // For meals, tracks if ingredients are loaded
    var ingredients: [SavedMealIngredient] = []

    init(food: SavedFood) {
        self.id = food.id
        self.food = food
    }
}
