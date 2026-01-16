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
                } else if viewModel.dailySummaries.isEmpty {
                    Section {
                        Text("No entries yet.")
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(viewModel.dailySummaries, id: \.date) { summary in
                    Section(header: Text(viewModel.dateLabel(from: summary.date))) {
                        HistoryRow(summary: summary)
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
        .onReceive(NotificationCenter.default.publisher(for: .dayReset)) { _ in
            Task {
                await viewModel.loadHistory()
            }
        }
    }
}

private struct HistoryRow: View {
    let summary: DailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if summary.hasData {
                Text("Calories: \(Int(summary.calories)) / \(Int(summary.caloriesTarget))")
                Text("Protein: \(Int(summary.protein))g / \(Int(summary.proteinTarget))g")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Carbs: \(Int(summary.carbs))g / \(Int(summary.carbsTarget))g")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Fat: \(Int(summary.fat))g / \(Int(summary.fatTarget))g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
