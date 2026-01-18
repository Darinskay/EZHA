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
                    .tint(.blue)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.inputText ?? "Meal")
                .font(.headline)
            Text(
                "Calories: \(Int(entry.calories))  Protein: \(Int(entry.protein))g  Carbs: \(Int(entry.carbs))g  Fat: \(Int(entry.fat))g"
            )
                .font(.subheadline)
                .foregroundColor(.secondary)
            if entry.imagePath != nil {
                Text("Photo attached")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(TimeLabelFormatter.label(from: entry.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
