import SwiftUI

struct SavedFoodRow: View {
    let food: SavedFood

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(food.name)
                    .font(.headline)
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
            Text(detailText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String {
        if food.isMeal {
            return "Tap to log with custom portions"
        }
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
