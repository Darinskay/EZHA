import SwiftUI

struct SavedFoodRow: View {
    let food: SavedFood

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(food.name)
                .font(.headline)
            Text(detailText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String {
        let unit = food.unitType == .per100g ? "per 100g" : "per serving"
        let macros = displayMacros
        return "\(Int(round(macros.calories))) cal \u{2022} P \(Int(round(macros.protein))) \u{2022} C \(Int(round(macros.carbs))) \u{2022} F \(Int(round(macros.fat))) (\(unit))"
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
}
