import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var isPresentingAddLog = false
    @State private var entryPendingDelete: FoodEntry?
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
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
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

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
                        Task {
                            await viewModel.startNewDay()
                            NotificationCenter.default.post(name: .dayReset, object: nil)
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
                    .disabled(viewModel.isLoading)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

                Section(header: Text("Today's Progress")) {
                    if viewModel.entries.isEmpty {
                        Text("No items yet.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(viewModel.entries) { entry in
                        TodayEntryRow(entry: entry)
                    }
                    .onDelete { indexSet in
                        guard let index = indexSet.first else { return }
                        entryPendingDelete = viewModel.entries[index]
                        isShowingDeleteConfirm = true
                    }
                }
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
}

private struct TodayEntryRow: View {
    let entry: FoodEntry

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
        case "food_photo":
            return "Food photo"
        case "label_photo":
            return "Label photo"
        default:
            return "Unknown source"
        }
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
