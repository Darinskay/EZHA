import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var isPresentingAddLog = false
    @State private var isPresentingLogMeal = false
    @State private var entryPendingDelete: FoodEntry?
    @State private var isShowingDeleteConfirm = false
    @State private var isChoosingTarget = false
    @State private var expandedEntryIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                summarySection
                actionsSection
                progressSection
            }
            .navigationTitle("Today")
            .confirmationDialog(
                "Delete entry?",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let entry = entryPendingDelete else { return }
                    Task {
                        await viewModel.deleteEntry(id: entry.id)
                    }
                    entryPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    entryPendingDelete = nil
                }
            }
        }
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
        .sheet(isPresented: $isPresentingAddLog) {
            AddLogSheet()
        }
        .sheet(isPresented: $isPresentingLogMeal) {
            LogMealSheet()
        }
        .fullScreenCover(isPresented: $isChoosingTarget) {
            targetPicker
        }
        .task {
            await viewModel.loadToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .foodEntrySaved)) { _ in
            Task {
                await viewModel.loadToday()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dayReset)) { _ in
            Task {
                await viewModel.loadToday()
            }
        }
    }

    private func startNewDay(using target: DailyTarget) {
        Task {
            await viewModel.startNewDay(nextTarget: target)
            NotificationCenter.default.post(name: .dayReset, object: nil)
        }
    }

    private var targetPicker: some View {
        DailyTargetPickerView(
            targets: viewModel.availableTargets,
            onSelect: { target in
                startNewDay(using: target)
            },
            preselectedTargetId: viewModel.activeTarget?.id
        )
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            MacroProgressTable(
                targets: viewModel.targets,
                eaten: viewModel.totals
            )
            .redacted(reason: viewModel.isLoading ? .placeholder : [])
            .overlay(alignment: .topTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                        .padding(8)
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button {
                isPresentingAddLog = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                    Text("Add log")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.8, green: 0.2, blue: 0.6))
            .foregroundStyle(.white)
            .disabled(viewModel.isLoading)

            Button {
                isPresentingLogMeal = true
            } label: {
                HStack {
                    Image(systemName: "fork.knife")
                        .imageScale(.large)
                    Text("Log meal")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
            .disabled(viewModel.isLoading)

            Button {
                if viewModel.availableTargets.count <= 1 {
                    guard let target = viewModel.availableTargets.first ?? viewModel.activeTarget else {
                        viewModel.errorMessage = "Add a daily target first."
                        return
                    }
                    startNewDay(using: target)
                } else {
                    isChoosingTarget = true
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                    Text("Start New Day")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.indigo)
            .disabled(viewModel.isLoading)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }

    @ViewBuilder
    private var progressSection: some View {
        Section(header: Text("Today's Progress")) {
            if viewModel.entriesWithItems.isEmpty {
                Text("No items yet.")
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.entriesWithItems) { entryWithItems in
                TodayEntryRow(
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
            .onDelete { indexSet in
                guard let index = indexSet.first else { return }
                entryPendingDelete = viewModel.entriesWithItems[index].entry
                isShowingDeleteConfirm = true
            }
        }
    }
}

private struct TodayEntryRow: View {
    let entryWithItems: FoodEntryWithItems
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var entry: FoodEntry { entryWithItems.entry }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entryTitle)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(TimeLabelFormatter.label(from: entry.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if entry.imagePath != nil {
                            TagView(text: "Photo", systemImage: "photo")
                        }
                    }
                }
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
                Spacer(minLength: 0)
                if let confidenceLabel {
                    TagView(text: confidenceLabel, systemImage: "sparkles")
                }
                TagView(text: sourceLabel)
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
                            EntryItemRow(item: item)
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

    private var confidenceLabel: String? {
        guard let confidence = entry.aiConfidence else { return nil }
        let percent = Int((confidence * 100).rounded())
        return "AI \(percent)%"
    }

    private var sourceLabel: String {
        switch entry.aiSource {
        case "library":
            return "Library"
        case "text":
            return "AI: text description"
        case "food_photo":
            return "AI: photo"
        case "label_photo":
            return "AI: photo"
        case "unknown":
            return entry.imagePath != nil ? "AI: photo" : "AI: text description"
        default:
            return "Unknown source"
        }
    }
}

private struct EntryItemRow: View {
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

private struct TagView: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private enum TimeLabelFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func label(from date: Date?) -> String {
        guard let date else { return "Time unavailable" }
        return formatter.string(from: date)
    }
}
