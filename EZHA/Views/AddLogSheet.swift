import PhotosUI
import SwiftUI

struct AddLogSheet: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @EnvironmentObject private var logStore: FoodLogStore
    @StateObject private var viewModel = AddLogViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Input Type") {
                    Picker("Input", selection: $viewModel.inputType) {
                        ForEach(LogInputType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.isPhotoEnabled {
                    Section("Photo") {
                        PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                            Label("Select Photo", systemImage: "photo")
                        }
                        if viewModel.selectedImageData != nil {
                            Text("Photo attached")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if viewModel.isTextEnabled {
                    Section("Meal Description") {
                        TextEditor(text: $viewModel.inputText)
                            .frame(minHeight: 120)
                    }
                }

                Section {
                    Button {
                        Task {
                            await viewModel.analyze()
                        }
                    } label: {
                        if viewModel.isAnalyzing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Analyze")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.isAnalyzing || (!viewModel.isTextEnabled && !viewModel.isPhotoEnabled))
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }

                if viewModel.estimate != nil {
                    Section("Edit Estimate") {
                        MacroEditField(label: "Calories", value: $viewModel.caloriesText)
                        MacroEditField(label: "Protein (g)", value: $viewModel.proteinText)
                        MacroEditField(label: "Carbs (g)", value: $viewModel.carbsText)
                        MacroEditField(label: "Fat (g)", value: $viewModel.fatText)
                    }

                    Section {
                        Button("Save") {
                            if let entry = viewModel.buildEntry() {
                                logStore.add(entry)
                                viewModel.reset()
                                dismiss()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Add Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task(id: viewModel.selectedItem) {
                await viewModel.loadSelectedImage()
            }
        }
    }
}

private struct MacroEditField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        TextField(label, text: $value)
            .keyboardType(.numberPad)
    }
}
