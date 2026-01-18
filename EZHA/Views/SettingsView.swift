import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Targets") {
                    LabeledContent("Calories") {
                        TextField("", text: $viewModel.caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("", text: $viewModel.proteinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("", text: $viewModel.carbsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("", text: $viewModel.fatText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

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
            .dismissKeyboardOnTap()
        }
        .task {
            await viewModel.loadTargets()
        }
    }
}
