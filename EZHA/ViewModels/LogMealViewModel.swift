import Foundation
import PhotosUI
import SwiftUI

struct MealLibrarySelection: Identifiable, Hashable {
    let id: UUID
    var food: SavedFood
    var gramsText: String
    var errorMessage: String?

    init(food: SavedFood, gramsText: String = "", errorMessage: String? = nil) {
        self.id = food.id
        self.food = food
        self.gramsText = gramsText
        self.errorMessage = errorMessage
    }
}

@MainActor
final class LogMealViewModel: ObservableObject {
    @Published var mealName: String = ""
    @Published var descriptionText: String = ""
    @Published var selectedItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    @Published var isLabelPhoto: Bool = false
    @Published var labelGramsText: String = ""
    @Published var librarySelections: [MealLibrarySelection] = []
    @Published var estimate: MacroEstimate? = nil
    @Published var isAnalyzing: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String? = nil
    @Published var analysisStage: AnalysisStage = .idle
    @Published var streamPreview: String = ""
    @Published var showSaveToLibrary: Bool = false

    private var pendingEntryId: UUID? = nil
    private var pendingImagePath: String? = nil
    private var streamBuffer: String = ""
    private var labelBaseEstimate: MacroEstimate? = nil
    private var isApplyingLabelScale: Bool = false

    private let analysisService: AIAnalysisService
    private let entryRepository: FoodEntryRepository
    private let profileRepository: ProfileRepository
    private let storageService: StorageService
    private let savedFoodRepository: SavedFoodRepository

    init(
        analysisService: AIAnalysisService = AIAnalysisService(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        profileRepository: ProfileRepository = ProfileRepository(),
        storageService: StorageService = StorageService(),
        savedFoodRepository: SavedFoodRepository = SavedFoodRepository()
    ) {
        self.analysisService = analysisService
        self.entryRepository = entryRepository
        self.profileRepository = profileRepository
        self.storageService = storageService
        self.savedFoodRepository = savedFoodRepository
    }

    var suggestedMealName: String {
        let libraryNames = librarySelections.map { $0.food.name }
        let aiName = estimate?.foodName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        parts.append(contentsOf: libraryNames)
        if let aiName, !aiName.isEmpty {
            parts.append(aiName)
        }
        if parts.isEmpty, !description.isEmpty {
            return description
        }
        if parts.isEmpty {
            return "Meal"
        }
        return parts.joined(separator: " + ")
    }

    var hasTextOrPhotoInput: Bool {
        let hasText = !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = selectedImageData != nil || pendingImagePath != nil
        return hasText || hasPhoto
    }

    var canAnalyze: Bool {
        return !isAnalyzing && hasTextOrPhotoInput
    }

    var libraryTotals: MacroDoubles {
        librarySelections.reduce(into: MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, item in
            guard let grams = parseMacro(item.gramsText), grams > 0 else { return }
            let totals = item.food.macroDoubles(for: grams)
            partial = MacroDoubles(
                calories: partial.calories + totals.calories,
                protein: partial.protein + totals.protein,
                carbs: partial.carbs + totals.carbs,
                fat: partial.fat + totals.fat
            )
        }
    }

    var combinedTotals: MacroDoubles? {
        let library = libraryTotals
        let aiTotals = estimate.map { MacroDoubles(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat) }
        if aiTotals == nil && library.calories == 0 && library.protein == 0 && library.carbs == 0 && library.fat == 0 {
            return nil
        }
        if let aiTotals {
            return MacroDoubles(
                calories: library.calories + aiTotals.calories,
                protein: library.protein + aiTotals.protein,
                carbs: library.carbs + aiTotals.carbs,
                fat: library.fat + aiTotals.fat
            )
        }
        return library
    }

    var canSaveMeal: Bool {
        let hasLibrary = librarySelections.contains { parseMacro($0.gramsText) != nil }
        let hasAI = estimate != nil
        if hasTextOrPhotoInput && !hasAI {
            return false
        }
        return hasLibrary || hasAI
    }

    func loadSelectedImage() async {
        guard let selectedItem else { return }
        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                pendingEntryId = nil
                pendingImagePath = nil
                isLabelPhoto = false
                labelGramsText = ""
                labelBaseEstimate = nil
            }
        } catch {
            errorMessage = "Unable to load photo."
        }
    }

    func handleLabelToggle(_ isOn: Bool) {
        if !isOn {
            if let base = labelBaseEstimate {
                updateEstimateFromBase(base)
            }
            labelGramsText = ""
            labelBaseEstimate = nil
        }
    }

    func applyLabelScaling() {
        guard !isApplyingLabelScale else { return }
        guard isLabelPhoto else { return }
        guard let grams = parseMacro(labelGramsText), grams > 0 else { return }
        let multiplier = grams / 100.0
        guard multiplier > 0 else { return }

        let base = labelBaseEstimate ?? estimateFromCurrentFields()
        guard let base else { return }

        isApplyingLabelScale = true
        let scaled = MacroEstimate(
            calories: base.calories * multiplier,
            protein: base.protein * multiplier,
            carbs: base.carbs * multiplier,
            fat: base.fat * multiplier,
            confidence: base.confidence,
            source: base.source,
            foodName: base.foodName,
            notes: base.notes,
            items: base.items
        )
        updateEstimateFromBase(scaled)
        isApplyingLabelScale = false
    }

    func analyze() async {
        guard canAnalyze else { return }
        isAnalyzing = true
        errorMessage = nil
        analysisStage = .preparing
        streamPreview = ""
        streamBuffer = ""
        estimate = nil
        showSaveToLibrary = false
        defer { isAnalyzing = false }

        do {
            let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

            if let imageData = selectedImageData, pendingImagePath == nil {
                analysisStage = .uploading
                let userId = try await SupabaseConfig.currentUserId()
                let entryId = pendingEntryId ?? UUID()
                pendingEntryId = entryId
                pendingImagePath = try await storageService.uploadFoodImage(
                    data: imageData,
                    userId: userId,
                    entryId: entryId
                )
            }

            analysisStage = .requestingModel
            let stream = try await analysisService.analyzeStream(
                text: description.isEmpty ? "" : description,
                items: nil,
                imagePath: pendingImagePath,
                inputType: analysisInputType
            )

            for try await event in stream {
                switch event {
                case .status(let stage):
                    analysisStage = AnalysisStage(from: stage)
                case .delta(let delta):
                    analysisStage = .streaming
                    appendStream(delta)
                case .result(let result):
                    analysisStage = .finalizing
                    estimate = result
                    streamPreview = ""
                    showSaveToLibrary = true
                    if isLabelPhoto {
                        labelBaseEstimate = result
                        applyLabelScaling()
                    }
                case .error(let message):
                    throw AnalysisError.remote(message)
                }
            }

            if estimate == nil {
                let fallback = try await analysisService.analyze(
                    text: description.isEmpty ? "" : description,
                    items: nil,
                    imagePath: pendingImagePath,
                    inputType: analysisInputType
                )
                estimate = fallback
                streamPreview = ""
                analysisStage = .idle
                showSaveToLibrary = true
                if isLabelPhoto {
                    labelBaseEstimate = fallback
                    applyLabelScaling()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            analysisStage = .idle
        }
    }

    func saveMeal(mealName: String, saveToLibrary: Bool, libraryName: String?) async -> Bool {
        guard let totals = combinedTotals else {
            errorMessage = "Add at least one item or analyze the meal."
            return false
        }
        if saveToLibrary, let libraryName {
            guard validateLibraryName(libraryName) else { return false }
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let entryId = pendingEntryId ?? UUID()
            let activeDate = try await resolvedActiveDate(for: userId)

            var imagePath: String? = pendingImagePath
            if imagePath == nil, let imageData = selectedImageData {
                imagePath = try await storageService.uploadFoodImage(
                    data: imageData,
                    userId: userId,
                    entryId: entryId
                )
            }

            let source = estimate?.source ?? "library"
            let confidence = estimate?.confidence
            let notes = estimate?.notes ?? "Saved foods"
            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: activeDate,
                inputType: resolvedInputType.databaseValue,
                inputText: mealName,
                imagePath: imagePath,
                calories: totals.calories,
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat,
                aiConfidence: confidence,
                aiSource: source,
                aiNotes: notes,
                createdAt: nil
            )

            try await entryRepository.insertFoodEntry(entry, items: [])

            if saveToLibrary, let libraryName {
                guard let draft = buildLibraryDraft(name: libraryName, totals: totals) else { return false }
                try await savedFoodRepository.insertFood(draft)
            }

            return true
        } catch {
            errorMessage = "Unable to save entry: \(error.localizedDescription)"
            return false
        }
    }

    func validateLibraryName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Please enter a food name to save to Library."
            return false
        }
        return true
    }

    func buildLibraryDraft(name: String, totals: MacroDoubles) -> SavedFoodDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a food name to save to Library."
            return nil
        }

        return SavedFoodDraft(
            name: trimmed,
            unitType: .per100g,
            servingSize: nil,
            servingUnit: nil,
            caloriesPer100g: totals.calories,
            proteinPer100g: totals.protein,
            carbsPer100g: totals.carbs,
            fatPer100g: totals.fat,
            caloriesPerServing: 0,
            proteinPerServing: 0,
            carbsPerServing: 0,
            fatPerServing: 0
        )
    }

    func clearPhoto() {
        selectedItem = nil
        selectedImageData = nil
        pendingEntryId = nil
        pendingImagePath = nil
        isLabelPhoto = false
        labelGramsText = ""
        labelBaseEstimate = nil
    }

    func reset() {
        mealName = ""
        descriptionText = ""
        selectedItem = nil
        selectedImageData = nil
        isLabelPhoto = false
        labelGramsText = ""
        librarySelections = []
        estimate = nil
        isAnalyzing = false
        isSaving = false
        errorMessage = nil
        analysisStage = .idle
        streamPreview = ""
        streamBuffer = ""
        pendingEntryId = nil
        pendingImagePath = nil
        labelBaseEstimate = nil
        showSaveToLibrary = false
    }

    func updateLibrarySelections(_ selections: [MealLibrarySelection]) {
        librarySelections = selections
        errorMessage = nil
    }

    func updateLibrarySelection(id: UUID, gramsText: String) {
        guard let index = librarySelections.firstIndex(where: { $0.id == id }) else { return }
        librarySelections[index].gramsText = gramsText
        librarySelections[index].errorMessage = nil
    }

    func removeLibrarySelection(id: UUID) {
        librarySelections.removeAll { $0.id == id }
    }

    func validateLibrarySelections() -> Bool {
        var isValid = true
        for index in librarySelections.indices {
            guard let grams = parseMacro(librarySelections[index].gramsText), grams > 0 else {
                librarySelections[index].errorMessage = "Enter grams."
                isValid = false
                continue
            }
            librarySelections[index].errorMessage = nil
        }
        return isValid
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

    private var analysisInputType: String {
        if isLabelPhoto, selectedImageData != nil || pendingImagePath != nil {
            return "label_photo"
        }
        return resolvedInputType.databaseValue
    }

    private var resolvedInputType: LogInputType {
        let hasText = !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = selectedImageData != nil || pendingImagePath != nil
        switch (hasPhoto, hasText) {
        case (true, true):
            return .photoText
        case (true, false):
            return .photo
        case (false, true):
            return .text
        case (false, false):
            return .text
        }
    }

    private func appendStream(_ delta: String) {
        streamBuffer.append(delta)
        let maxBuffer = 2200
        if streamBuffer.count > maxBuffer {
            streamBuffer = String(streamBuffer.suffix(maxBuffer))
        }

        let maxPreview = 480
        if streamBuffer.count > maxPreview {
            streamPreview = "..." + streamBuffer.suffix(maxPreview)
        } else {
            streamPreview = streamBuffer
        }
    }

    private func estimateFromCurrentFields() -> MacroEstimate? {
        guard let current = estimate else { return nil }
        return current
    }

    private func updateEstimateFromBase(_ base: MacroEstimate) {
        estimate = base
    }

    private func resolvedActiveDate(for userId: UUID) async throws -> String {
        if let profile = try await profileRepository.fetchProfile() {
            return profile.activeDate
        }
        let dateString = Self.dateFormatter.string(from: Date())
        let defaultProfile = Profile.defaultTargets(for: userId, activeDate: dateString)
        try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)
        return dateString
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
