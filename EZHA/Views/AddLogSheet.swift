import PhotosUI
import SwiftUI
import UIKit

struct AddLogSheet: View {
    @Environment(
        \.dismiss
    ) private var dismiss
    @StateObject private var viewModel = AddLogViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $viewModel.selectedItem, matching: .images) {
                        Label("Select Photo", systemImage: "photo")
                    }
                    if let imageData = viewModel.selectedImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("No photo selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Meal Description") {
                    TextEditor(text: $viewModel.inputText)
                        .frame(minHeight: 120)
                }

                Button {
                    Task {
                        dismissKeyboard()
                        await viewModel.analyze()
                    }
                } label: {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text("Analyze")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .disabled(!viewModel.canAnalyze)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)

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
                        Button {
                            Task {
                                let didSave = await viewModel.saveEntry()
                                if didSave {
                                    viewModel.reset()
                                    dismiss()
                                    NotificationCenter.default.post(name: .foodEntrySaved, object: nil)
                                }
                            }
                        } label: {
                            if viewModel.isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isSaving)
                    }
                }
            }
            .navigationTitle("Add Log")
            .dismissKeyboardOnTap()
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
        LabeledContent(label) {
            TextField("", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct KeyboardDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let gesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        @objc func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissView())
    }
}

private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
