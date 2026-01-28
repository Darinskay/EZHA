import SwiftUI

struct DailyTargetEditorView: View {
    let target: DailyTarget?
    let onSave: (DailyTargetInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var errorMessage: String?

    init(target: DailyTarget?, onSave: @escaping (DailyTargetInput) -> Void) {
        self.target = target
        self.onSave = onSave
        _name = State(initialValue: target?.name ?? "")
        _caloriesText = State(initialValue: Self.formatValue(target?.caloriesTarget))
        _proteinText = State(initialValue: Self.formatValue(target?.proteinTarget))
        _carbsText = State(initialValue: Self.formatValue(target?.carbsTarget))
        _fatText = State(initialValue: Self.formatValue(target?.fatTarget))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Basic", text: $name)
                }

                Section("Macros") {
                    LabeledContent("Calories") {
                        TextField("", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein (g)") {
                        TextField("", text: $proteinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Carbs (g)") {
                        TextField("", text: $carbsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat (g)") {
                        TextField("", text: $fatText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(target == nil ? "New Target" : "Edit Target")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveTarget()
                    }
                }
            }
        }
        .dismissKeyboardOnTap()
        .keyboardDoneToolbar()
    }

    private func saveTarget() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a name for this target."
            return
        }
        guard let calories = Double(caloriesText),
              let protein = Double(proteinText),
              let carbs = Double(carbsText),
              let fat = Double(fatText) else {
            errorMessage = "Enter valid numbers for targets."
            return
        }

        onSave(
            DailyTargetInput(
                id: target?.id,
                name: trimmedName,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            )
        )
        dismiss()
    }

    private static func formatValue(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(Int(round(value)))
    }
}
