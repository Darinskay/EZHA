import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var expandedDate: String?
    @State private var expandedEntryIds: Set<UUID> = []

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
                ForEach(Array(viewModel.dailySummaries.enumerated()), id: \.element.date) { index, summary in
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(isExpanded: binding(for: summary.date)) {
                            HistoryEntriesList(
                                date: summary.date,
                                entriesWithItemsByDate: viewModel.entriesWithItemsByDate,
                                loadingDates: viewModel.loadingDates,
                                entryErrors: viewModel.entryErrors,
                                expandedEntryIds: $expandedEntryIds
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.dateLabel(from: summary.date))
                                    .font(.headline)
                                HistoryRow(summary: summary)
                            }
                            .padding(.vertical, 4)
                        }

                        if index == 0 && viewModel.isActiveDateToday {
                            Button {
                                Task {
                                    await viewModel.goToDate(summary.date)
                                    NotificationCenter.default.post(name: .activeDateChanged, object: nil)
                                }
                            } label: {
                                Text("Go to this date")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
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
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
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
        .onReceive(NotificationCenter.default.publisher(for: .activeDateChanged)) { _ in
            Task {
                await viewModel.loadHistory()
            }
        }
    }
}

private extension HistoryView {
    func binding(for date: String) -> Binding<Bool> {
        Binding(
            get: { expandedDate == date },
            set: { isExpanded in
                withAnimation(.easeInOut) {
                    expandedDate = isExpanded ? date : nil
                }
                if isExpanded {
                    Task {
                        await viewModel.loadEntries(for: date)
                    }
                }
            }
        )
    }
}

private struct HistoryRow: View {
    let summary: DailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let targetName = summary.dailyTargetName, !targetName.isEmpty {
                Text("Target: \(targetName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if summary.hasData {
                Text("Calories: \(Int(summary.calories)) / \(Int(summary.caloriesTarget)) (\(percent(summary.calories, target: summary.caloriesTarget))%)")
                Text("Protein: \(Int(summary.protein))g / \(Int(summary.proteinTarget))g (\(percent(summary.protein, target: summary.proteinTarget))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Carbs: \(Int(summary.carbs))g / \(Int(summary.carbsTarget))g (\(percent(summary.carbs, target: summary.carbsTarget))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Fat: \(Int(summary.fat))g / \(Int(summary.fatTarget))g (\(percent(summary.fat, target: summary.fatTarget))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func percent(_ value: Double, target: Double) -> Int {
        guard target > 0 else { return 0 }
        return Int(((value / target) * 100).rounded())
    }
}

private struct HistoryEntriesList: View {
    let date: String
    let entriesWithItemsByDate: [String: [FoodEntryWithItems]]
    let loadingDates: Set<String>
    let entryErrors: [String: String]
    @Binding var expandedEntryIds: Set<UUID>

    var body: some View {
        if loadingDates.contains(date) {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let errorMessage = entryErrors[date] {
            Text(errorMessage)
                .foregroundColor(.red)
        } else if let entries = entriesWithItemsByDate[date], entries.isEmpty {
            Text("No items logged.")
                .foregroundColor(.secondary)
        } else if let entries = entriesWithItemsByDate[date] {
            ForEach(entries) { entryWithItems in
                HistoryEntryRow(
                    entryWithItems: entryWithItems,
                    isExpanded: expandedEntryIds.contains(entryWithItems.id),
                    onToggleExpand: {
                        if expandedEntryIds.contains(entryWithItems.id) {
                            expandedEntryIds.remove(entryWithItems.id)
                        } else {
                            expandedEntryIds.insert(entryWithItems.id)
                        }
                    }
                )
            }
        }
    }
}

private struct HistoryEntryRow: View {
    let entryWithItems: FoodEntryWithItems
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var entry: FoodEntry { entryWithItems.entry }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entryTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(entry.calories))")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 6) {
                MacroChip(label: "P", value: entry.protein, tint: .orange)
                MacroChip(label: "C", value: entry.carbs, tint: .blue)
                MacroChip(label: "F", value: entry.fat, tint: .pink)
            }

            if entryWithItems.hasItems {
                Button(action: onToggleExpand) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide details" : "Show details")
                            .font(.caption)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entryWithItems.items) { item in
                            HistoryItemRow(item: item)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var entryTitle: String {
        let trimmed = entry.inputText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed ?? "Meal" : "Meal"
    }
}

private struct HistoryItemRow: View {
    let item: FoodEntryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formattedGrams(item.grams))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                MacroChip(label: "Cal", value: item.calories, tint: .purple)
                MacroChip(label: "P", value: item.protein, tint: .orange)
                MacroChip(label: "C", value: item.carbs, tint: .blue)
                MacroChip(label: "F", value: item.fat, tint: .pink)
                Spacer()
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formattedGrams(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        if let text = formatter.string(from: NSNumber(value: value)) {
            return "\(text) g"
        }
        return "\(value) g"
    }
}

private struct MacroChip: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
            Text("\(Int(value))g")
                .font(.caption2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .foregroundColor(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
