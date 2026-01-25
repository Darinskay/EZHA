import SwiftUI

struct FoodEditorView: View {
    let food: SavedFood?
    let onSave: (SavedFoodDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var unitType: FoodUnitType = .per100g
    @State private var servingSizeText: String = ""
    @State private var servingUnit: String = "serving"
    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Food name", text: $name)
                }

                Section("Units") {
                    Picker("Unit type", selection: $unitType) {
                        ForEach(FoodUnitType.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    if unitType == .perServing {
                        HStack(spacing: 12) {
                            TextField("Grams", text: $servingSizeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            TextField("Unit", text: $servingUnit)
                                .textInputAutocapitalization(.never)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                Section("Macros") {
                    if unitType == .perServing {
                        perServingPreviewRow(label: "Calories", value: perServingDisplay?.calories)
                        perServingPreviewRow(label: "Protein (g)", value: perServingDisplay?.protein)
                        perServingPreviewRow(label: "Carbs (g)", value: perServingDisplay?.carbs)
                        perServingPreviewRow(label: "Fat (g)", value: perServingDisplay?.fat)
                        Text("Per serving values are calculated from per 100g.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Edit per 100g values") {
                            unitType = .per100g
                        }
                        .font(.subheadline)
                    } else {
                        LabeledContent("Calories") {
                            TextField("", text: $caloriesText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Protein (g)") {
                            TextField("", text: $proteinText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Carbs (g)") {
                            TextField("", text: $carbsText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Fat (g)") {
                            TextField("", text: $fatText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
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
            .navigationTitle(food == nil ? "Add Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await handleSave() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear(perform: populate)
            .keyboardDoneToolbar()
        }
    }

    private func populate() {
        guard let food else { return }
        name = food.name
        unitType = food.unitType
        if let servingSize = food.servingSize {
            servingSizeText = String(servingSize)
        }
        servingUnit = food.servingUnit ?? "serving"
        caloriesText = formatMacro(food.caloriesPer100g)
        proteinText = formatMacro(food.proteinPer100g)
        carbsText = formatMacro(food.carbsPer100g)
        fatText = formatMacro(food.fatPer100g)
    }

    private func handleSave() async {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a name."
            return
        }

        guard let calories = parseMacro(caloriesText),
              let protein = parseMacro(proteinText),
              let carbs = parseMacro(carbsText),
              let fat = parseMacro(fatText) else {
            errorMessage = unitType == .perServing
                ? "Enter per 100g macros to calculate per serving."
                : "Please enter valid macro values."
            return
        }

        var servingSize: Double? = nil
        var servingLabel: String? = nil
        if unitType == .perServing {
            if let size = Double(servingSizeText) {
                servingSize = size
            }
            let trimmedUnit = servingUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            servingLabel = trimmedUnit.isEmpty ? nil : trimmedUnit
        }
        if unitType == .perServing {
            guard let servingSize, servingSize > 0 else {
                errorMessage = "Please enter grams per serving."
                return
            }
        }

        let perServing = computePerServing(
            per100g: MacroDoubles(calories: calories, protein: protein, carbs: carbs, fat: fat),
            servingSize: servingSize
        )

        let draft = SavedFoodDraft(
            name: trimmedName,
            unitType: unitType,
            servingSize: servingSize,
            servingUnit: servingLabel,
            caloriesPer100g: calories,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            caloriesPerServing: perServing.calories,
            proteinPerServing: perServing.protein,
            carbsPerServing: perServing.carbs,
            fatPerServing: perServing.fat
        )

        isSaving = true
        let didSave = await onSave(draft)
        isSaving = false
        if didSave {
            dismiss()
        }
    }

    private func parseMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = normalizedNumberString(trimmed)
        return Double(normalized)
    }

    private func normalizedNumberString(_ text: String) -> String {
        let noSpaces = text.replacingOccurrences(of: " ", with: "")
        if noSpaces.contains(",") && !noSpaces.contains(".") {
            return noSpaces.replacingOccurrences(of: ",", with: ".")
        }
        return noSpaces
    }

    private func formatMacro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        if let text = formatter.string(from: NSNumber(value: value)) {
            return text
        }
        return String(value)
    }

    private func computePerServing(per100g: MacroDoubles, servingSize: Double?) -> MacroDoubles {
        guard let servingSize, servingSize > 0 else {
            return MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
        }
        let multiplier = servingSize / 100.0
        return MacroDoubles(
            calories: per100g.calories * multiplier,
            protein: per100g.protein * multiplier,
            carbs: per100g.carbs * multiplier,
            fat: per100g.fat * multiplier
        )
    }

    private var perServingDisplay: MacroDoubles? {
        guard let per100g = per100gInputs else { return nil }
        return computePerServing(per100g: per100g, servingSize: Double(servingSizeText))
    }

    private var per100gInputs: MacroDoubles? {
        guard let calories = parseMacro(caloriesText),
              let protein = parseMacro(proteinText),
              let carbs = parseMacro(carbsText),
              let fat = parseMacro(fatText) else {
            return nil
        }
        return MacroDoubles(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    private func perServingPreviewRow(label: String, value: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.map(formatMacro) ?? "--")
                .foregroundColor(.secondary)
        }
    }
}
