import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = SettingsViewModel()
    @State private var editorContext: DailyTargetEditorContext?
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Targets") {
                    if viewModel.targets.isEmpty {
                        Text("No targets yet.")
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.targets) { target in
                        Button {
                            editorContext = DailyTargetEditorContext(target: target)
                        } label: {
                            DailyTargetRow(target: target)
                        }
                        .foregroundColor(.primary)
                    }
                    .onDelete { indexSet in
                        guard viewModel.targets.count > 1 else {
                            viewModel.errorMessage = "At least one target is required."
                            return
                        }
                        for index in indexSet {
                            let target = viewModel.targets[index]
                            Task {
                                await viewModel.deleteTarget(id: target.id)
                            }
                        }
                    }

                    Button {
                        editorContext = DailyTargetEditorContext(target: nil)
                    } label: {
                        Label("Add Target", systemImage: "plus")
                    }
                    .disabled(viewModel.isLoading)
                }

                Section("Appearance") {
                    Picker("App theme", selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title)
                                .tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let saveMessage = viewModel.saveMessage {
                    Section {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.6))
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await sessionManager.signOut()
                        }
                    } label: {
                        Text("Sign out")
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
        .task {
            await viewModel.loadTargets()
        }
        .sheet(item: $editorContext) { context in
            DailyTargetEditorView(target: context.target) { input in
                Task {
                    await viewModel.saveTarget(input)
                }
            }
        }
    }
}

private struct DailyTargetRow: View {
    let target: DailyTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.name)
                .font(.headline)
            HStack(spacing: 12) {
                TargetValue(label: "Cals", value: target.caloriesTarget, unit: "kcal")
                TargetValue(label: "P", value: target.proteinTarget, unit: "g")
                TargetValue(label: "C", value: target.carbsTarget, unit: "g")
                TargetValue(label: "F", value: target.fatTarget, unit: "g")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TargetValue: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        Text("\(label): \(Int(round(value)))\(unit)")
    }
}

private struct DailyTargetEditorContext: Identifiable {
    let id = UUID()
    let target: DailyTarget?
}
