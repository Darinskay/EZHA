import SwiftUI

struct MacroProgressTable: View {
    let targets: MacroTargets
    let eaten: MacroTotals

    var body: some View {
        VStack(spacing: 8) {
            MacroRow(label: "Calories", target: targets.calories, eaten: eaten.calories)
            MacroRow(label: "Protein", target: targets.protein, eaten: eaten.protein, unit: "g")
            MacroRow(label: "Carbs", target: targets.carbs, eaten: eaten.carbs, unit: "g")
            MacroRow(label: "Fat", target: targets.fat, eaten: eaten.fat, unit: "g")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacroRow: View {
    let label: String
    let target: Int
    let eaten: Int
    var unit: String = ""

    var remaining: Int {
        max(target - eaten, 0)
    }

    var percentage: Double {
        guard target > 0 else { return 0 }
        return Double(eaten) / Double(target)
    }

    private var percentageTextColor: Color {
        let percent = Int((percentage * 100).rounded())
        if percent >= 101 {
            return .red
        }
        if percent >= 81 {
            return .green
        }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(Int(round(percentage * 100)))%")
                    .font(.subheadline)
                    .foregroundColor(percentageTextColor)
            }
            HStack {
                Text("Target: \(target)\(unit)")
                Spacer()
                Text("Eaten: \(eaten)\(unit)")
                Spacer()
                Text("Remaining: \(remaining)\(unit)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            ProgressView(value: min(percentage, 1))
        }
    }
}
