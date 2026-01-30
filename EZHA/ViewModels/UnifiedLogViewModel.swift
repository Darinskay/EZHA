import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class UnifiedLogViewModel: ObservableObject {
    // MARK: - Items
    @Published var items: [LogItem] = []

    // MARK: - Source States
    @Published var photoUsed: Bool = false
    @Published var textUsed: Bool = false
    @Published var selectedImageData: Data?
    @Published var selectedPhotosItem: PhotosPickerItem? = nil
    @Published var descriptionText: String = ""

    // MARK: - Label Photo
    @Published var isLabelPhoto: Bool = false
    @Published var labelGramsText: String = ""
    @Published var labelCaloriesText: String = ""
    @Published var labelProteinText: String = ""
    @Published var labelCarbsText: String = ""
    @Published var labelFatText: String = ""
    private var labelBaseEstimate: MacroEstimate? = nil
    private var isApplyingLabelScale: Bool = false

    // MARK: - AI Analysis State
    @Published var isAnalyzing: Bool = false
    @Published var streamPreview: String = ""
    @Published var analysisError: String?

    // MARK: - Save to Library
    @Published var saveToLibrary: Bool = false
    @Published var libraryName: String = ""

    // MARK: - General State
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?

    // MARK: - Services
    private let aiService = AIAnalysisService()
    private let entryRepository = FoodEntryRepository()
    private let storageService = StorageService()
    private let savedFoodRepository = SavedFoodRepository()

    // MARK: - Computed Properties

    var totalMacros: MacroDoubles {
        let totals = items.reduce((cal: 0.0, pro: 0.0, carb: 0.0, fat: 0.0)) { result, item in
            let m = item.macros
            return (
                result.cal + m.calories,
                result.pro + m.protein,
                result.carb + m.carbs,
                result.fat + m.fat
            )
        }
        return MacroDoubles(
            calories: totals.cal,
            protein: totals.pro,
            carbs: totals.carb,
            fat: totals.fat
        )
    }

    var canSave: Bool {
        !items.isEmpty && !isSaving && !isAnalyzing
    }

    var hasContent: Bool {
        !items.isEmpty || selectedImageData != nil || !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Item Management

    func addLibraryItems(_ foods: [SavedFood]) {
        for food in foods {
            let item = LogItem(from: food, grams: 100)
            items.append(item)
        }
    }

    func addMealIngredients(_ ingredients: [SavedMealIngredient]) {
        for ingredient in ingredients {
            let item = LogItem(from: ingredient)
            items.append(item)
        }
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func updateItemGrams(id: UUID, grams: String) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].gramsText = grams
        }
    }

    // MARK: - Fetch Meal Ingredients

    func fetchMealIngredients(for meal: SavedFood) async -> [SavedMealIngredient] {
        do {
            return try await savedFoodRepository.fetchMealIngredients(mealId: meal.id)
        } catch {
            errorMessage = "Failed to load meal ingredients: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Photo Handling

    func loadSelectedPhoto() async {
        guard let selectedPhotosItem else { return }
        do {
            if let data = try await selectedPhotosItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                isLabelPhoto = false
                labelGramsText = ""
                labelCaloriesText = ""
                labelProteinText = ""
                labelCarbsText = ""
                labelFatText = ""
                labelBaseEstimate = nil
            }
        } catch {
            analysisError = "Unable to load photo from gallery."
        }
    }

    func setCameraImage(_ data: Data?) {
        selectedPhotosItem = nil
        selectedImageData = data
        isLabelPhoto = false
        labelGramsText = ""
        labelCaloriesText = ""
        labelProteinText = ""
        labelCarbsText = ""
        labelFatText = ""
        labelBaseEstimate = nil
    }

    func clearPhoto() {
        selectedPhotosItem = nil
        selectedImageData = nil
        isLabelPhoto = false
        labelGramsText = ""
        labelCaloriesText = ""
        labelProteinText = ""
        labelCarbsText = ""
        labelFatText = ""
        labelBaseEstimate = nil
        photoUsed = false
    }

    func handleLabelToggle(_ isOn: Bool) {
        if !isOn, labelBaseEstimate != nil {
            // Clear label state when toggling off
            labelBaseEstimate = nil
            labelGramsText = ""
            labelCaloriesText = ""
            labelProteinText = ""
            labelCarbsText = ""
            labelFatText = ""
        }
    }

    func applyLabelScaling() {
        guard isLabelPhoto else { return }
        guard let base = labelBaseEstimate else { return }
        guard !isApplyingLabelScale else { return }
        isApplyingLabelScale = true
        defer { isApplyingLabelScale = false }
        guard let grams = Double(labelGramsText.trimmingCharacters(in: .whitespaces)), grams > 0 else {
            // Reset to base estimate if no valid grams
            updateItemsFromEstimate(base, source: "label_photo")
            syncLabelTextFields(with: base)
            return
        }

        let multiplier = grams / 100.0
        let scaled = MacroEstimate(
            calories: base.calories * multiplier,
            protein: base.protein * multiplier,
            carbs: base.carbs * multiplier,
            fat: base.fat * multiplier,
            confidence: base.confidence,
            source: base.source,
            foodName: base.foodName,
            notes: base.notes,
            items: base.items.map { item in
                MacroItemEstimate(
                    name: item.name,
                    grams: item.grams * multiplier,
                    calories: item.calories * multiplier,
                    protein: item.protein * multiplier,
                    carbs: item.carbs * multiplier,
                    fat: item.fat * multiplier,
                    confidence: item.confidence,
                    notes: item.notes
                )
            }
        )
        updateItemsFromEstimate(scaled, source: "label_photo")
        syncLabelTextFields(with: scaled)
    }

    func applyManualLabelEdits() {
        guard isLabelPhoto else { return }
        guard !isApplyingLabelScale else { return }
        guard let base = buildLabelBaseFromFields() else { return }
        labelBaseEstimate = base
        applyLabelScaling()
    }

    func saveLabelEntry() {
        guard isLabelPhoto else { return }
        guard let base = buildLabelBaseFromFields() else {
            analysisError = "Enter calories, protein, carbs, and fat before saving."
            return
        }
        labelBaseEstimate = base
        replaceLabelItemsFromFields()
        photoUsed = true
        analysisError = nil
    }

    private func updateItemsFromEstimate(_ estimate: MacroEstimate, source: String) {
        // Remove existing AI items only for the same source (keep text/photo combos)
        items.removeAll { $0.source == .ai && $0.aiSource == source }
        addItemsFromEstimate(estimate, source: source)
    }

    private func syncLabelTextFields(with estimate: MacroEstimate) {
        labelCaloriesText = formatMacro(estimate.calories)
        labelProteinText = formatMacro(estimate.protein)
        labelCarbsText = formatMacro(estimate.carbs)
        labelFatText = formatMacro(estimate.fat)
    }

    private func buildLabelBaseFromFields() -> MacroEstimate? {
        guard let calories = parseMacro(labelCaloriesText),
              let protein = parseMacro(labelProteinText),
              let carbs = parseMacro(labelCarbsText),
              let fat = parseMacro(labelFatText) else {
            return nil
        }

        let grams = parseMacro(labelGramsText) ?? 0
        let multiplier = grams > 0 ? grams / 100.0 : 1.0
        let targetBaseTotals = MacroEstimate(
            calories: calories / multiplier,
            protein: protein / multiplier,
            carbs: carbs / multiplier,
            fat: fat / multiplier,
            confidence: labelBaseEstimate?.confidence,
            source: labelBaseEstimate?.source ?? "label_photo",
            foodName: labelBaseEstimate?.foodName ?? "Nutrition label",
            notes: labelBaseEstimate?.notes ?? "",
            items: labelBaseEstimate?.items ?? []
        )

        let adjustedItems: [MacroItemEstimate]
        if !targetBaseTotals.items.isEmpty {
            var totals = (cal: 0.0, pro: 0.0, carb: 0.0, fat: 0.0)
            for item in targetBaseTotals.items {
                totals.cal += item.calories
                totals.pro += item.protein
                totals.carb += item.carbs
                totals.fat += item.fat
            }
            let calRatio = totals.cal > 0 ? targetBaseTotals.calories / totals.cal : 1
            let proRatio = totals.pro > 0 ? targetBaseTotals.protein / totals.pro : 1
            let carbRatio = totals.carb > 0 ? targetBaseTotals.carbs / totals.carb : 1
            let fatRatio = totals.fat > 0 ? targetBaseTotals.fat / totals.fat : 1
            adjustedItems = targetBaseTotals.items.map { item in
                MacroItemEstimate(
                    name: item.name,
                    grams: item.grams * calRatio,
                    calories: item.calories * calRatio,
                    protein: item.protein * proRatio,
                    carbs: item.carbs * carbRatio,
                    fat: item.fat * fatRatio,
                    confidence: item.confidence,
                    notes: item.notes
                )
            }
        } else {
            adjustedItems = [
                MacroItemEstimate(
                    name: "Nutrition label",
                    grams: 100,
                    calories: targetBaseTotals.calories,
                    protein: targetBaseTotals.protein,
                    carbs: targetBaseTotals.carbs,
                    fat: targetBaseTotals.fat,
                    confidence: nil,
                    notes: nil
                )
            ]
        }

        return MacroEstimate(
            calories: targetBaseTotals.calories,
            protein: targetBaseTotals.protein,
            carbs: targetBaseTotals.carbs,
            fat: targetBaseTotals.fat,
            confidence: targetBaseTotals.confidence,
            source: targetBaseTotals.source,
            foodName: targetBaseTotals.foodName,
            notes: targetBaseTotals.notes,
            items: adjustedItems
        )
    }

    private func replaceLabelItemsFromFields() {
        guard let calories = parseMacro(labelCaloriesText),
              let protein = parseMacro(labelProteinText),
              let carbs = parseMacro(labelCarbsText),
              let fat = parseMacro(labelFatText) else {
            return
        }

        let grams = parseMacro(labelGramsText) ?? 0
        let itemGrams = grams > 0 ? grams : 100
        let name = labelBaseEstimate?.foodName ?? "Nutrition label"

        // Remove existing label items regardless of aiSource tracking.
        items.removeAll { $0.source == .ai && ($0.aiSource == "label_photo" || $0.aiSource == nil) }

        let estimate = MacroEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: labelBaseEstimate?.confidence,
            source: "label_photo",
            foodName: name,
            notes: labelBaseEstimate?.notes ?? "",
            items: [
                MacroItemEstimate(
                    name: name,
                    grams: itemGrams,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    confidence: labelBaseEstimate?.confidence,
                    notes: nil
                )
            ]
        )

        addItemsFromEstimate(estimate, source: "label_photo")
    }

    // MARK: - AI Analysis

    func analyzePhoto() async {
        guard let imageData = selectedImageData else {
            analysisError = "No photo selected"
            return
        }

        isAnalyzing = true
        analysisError = nil
        streamPreview = ""

        do {
            // Upload image first
            let userId = try await SupabaseConfig.currentUserId()
            let tempEntryId = UUID()
            let imagePath = try await storageService.uploadFoodImage(
                data: imageData,
                userId: userId,
                entryId: tempEntryId
            )

            // Determine input type based on label toggle
            let inputType = isLabelPhoto ? "label_photo" : "food_photo"

            let direct = try await aiService.analyze(
                text: nil,
                items: nil,
                imagePath: imagePath,
                inputType: inputType
            )
            if isLabelPhoto {
                labelBaseEstimate = direct
                applyLabelScaling()
            } else {
                addItemsFromEstimate(direct, source: "food_photo")
            }
            photoUsed = true
            isAnalyzing = false
            streamPreview = ""
            analysisError = nil
        } catch {
            analysisError = error.localizedDescription
            isAnalyzing = false
        }
    }

    func analyzeText() async {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            analysisError = "Please enter a description"
            return
        }

        isAnalyzing = true
        analysisError = nil
        streamPreview = ""

        do {
            let direct = try await aiService.analyze(
                text: text,
                items: nil,
                imagePath: nil,
                inputType: "text"
            )
            addItemsFromEstimate(direct, source: "text")
            textUsed = true
            isAnalyzing = false
            streamPreview = ""
            analysisError = nil
        } catch {
            analysisError = error.localizedDescription
            isAnalyzing = false
        }
    }

    private func addItemsFromEstimate(_ estimate: MacroEstimate, source: String) {
        if estimate.items.isEmpty {
            // Single item estimate - create one item from totals
            let name = estimate.foodName ?? "Analyzed food"
            let item = LogItem(
                from: MacroItemEstimate(
                    name: name,
                    grams: 100,
                    calories: estimate.calories,
                    protein: estimate.protein,
                    carbs: estimate.carbs,
                    fat: estimate.fat,
                    confidence: estimate.confidence,
                    notes: estimate.notes
                ),
                source: source
            )
            items.append(item)
        } else {
            // Multiple items
            for aiItem in estimate.items {
                let item = LogItem(from: aiItem, source: source)
                items.append(item)
            }
        }
    }

    // MARK: - Save

    func saveLog() async -> Bool {
        guard canSave else { return false }

        isSaving = true
        errorMessage = nil

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let entryId = UUID()
            let totals = totalMacros

            // Determine input type and source
            let inputType: String
            let aiSource: String
            let hasPhoto = selectedImageData != nil
            let hasText = textUsed
            let hasLibrary = items.contains { $0.source == .library || $0.source == .meal }

            if hasPhoto && hasText {
                inputType = "photo+text"
                aiSource = isLabelPhoto ? "label_photo" : "food_photo"
            } else if hasPhoto {
                inputType = "photo"
                aiSource = isLabelPhoto ? "label_photo" : "food_photo"
            } else if hasText {
                inputType = "text"
                aiSource = "text"
            } else if hasLibrary {
                inputType = "text"
                aiSource = "library"
            } else {
                inputType = "text"
                aiSource = "unknown"
            }

            // Build input text from item names
            let inputText = items.map { $0.name }.joined(separator: ", ")

            // Upload image if present
            var imagePath: String? = nil
            if let imageData = selectedImageData {
                imagePath = try await storageService.uploadFoodImage(
                    data: imageData,
                    userId: userId,
                    entryId: entryId
                )
            }

            // Create entry
            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: currentDateString(),
                inputType: inputType,
                inputText: inputText,
                imagePath: imagePath,
                calories: totals.calories,
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat,
                aiConfidence: nil,
                aiSource: aiSource,
                aiNotes: "",
                createdAt: nil
            )

            // Create entry items
            let entryItems = items.map { item in
                FoodEntryItem(
                    id: UUID(),
                    entryId: entryId,
                    userId: userId,
                    name: item.name,
                    grams: item.grams,
                    calories: item.macros.calories,
                    protein: item.macros.protein,
                    carbs: item.macros.carbs,
                    fat: item.macros.fat,
                    aiConfidence: nil,
                    aiNotes: "",
                    createdAt: nil
                )
            }

            try await entryRepository.insertFoodEntry(entry, items: entryItems)

            // Save to library if requested
            if saveToLibrary && !libraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ingredientDrafts = items.map { item in
                    SavedMealIngredientDraft(
                        name: item.name,
                        grams: item.grams,
                        calories: item.macros.calories,
                        protein: item.macros.protein,
                        carbs: item.macros.carbs,
                        fat: item.macros.fat,
                        linkedFoodId: item.savedFood?.id
                    )
                }
                try await savedFoodRepository.insertMeal(
                    name: libraryName.trimmingCharacters(in: .whitespacesAndNewlines),
                    ingredients: ingredientDrafts
                )
            }

            // Post notification
            NotificationCenter.default.post(name: .foodEntrySaved, object: nil)

            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func parseMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatMacro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
