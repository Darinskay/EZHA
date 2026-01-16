import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Targets") {
                    TextField("Calories", text: $viewModel.caloriesText)
                        .keyboardType(.numberPad)
                    TextField("Protein (g)", text: $viewModel.proteinText)
                        .keyboardType(.numberPad)
                    TextField("Carbs (g)", text: $viewModel.carbsText)
                        .keyboardType(.numberPad)
                    TextField("Fat (g)", text: $viewModel.fatText)
                        .keyboardType(.numberPad)

                    Button("Save Targets") {
                        Task {
                            await viewModel.saveTargets()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }

                if let saveMessage = viewModel.saveMessage {
                    Section {
                        Text(saveMessage)
                            .font(.footnote)
                            .foregroundColor(.green)
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
        }
        .task {
            await viewModel.loadTargets()
        }
    }
}
