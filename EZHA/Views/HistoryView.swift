import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var logStore: FoodLogStore
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.recentTotals(from: logStore), id: \.date) { entry in
                    Section(header: Text(entry.date, style: .date)) {
                        HistoryRow(totals: entry.totals)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

private struct HistoryRow: View {
    let totals: MacroTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calories: \(totals.calories)")
            Text("Protein: \(totals.protein)g  Carbs: \(totals.carbs)g  Fat: \(totals.fat)g")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
