import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                } else if viewModel.dailyTotals.isEmpty {
                    Section {
                        Text("No entries yet.")
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(viewModel.dailyTotals, id: \.date) { entry in
                    Section(header: Text(entry.date, style: .date)) {
                        HistoryRow(totals: entry.totals)
                    }
                }
            }
            .navigationTitle("History")
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            await viewModel.loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .foodEntrySaved)) { _ in
            Task {
                await viewModel.loadHistory()
            }
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
