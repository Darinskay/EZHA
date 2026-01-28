import Foundation
import PhotosUI
import SwiftUI

struct FoodItemDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var gramsText: String = ""
}

struct SavedFoodQuickState: Hashable {
    var isActive: Bool = false
    var gramsText: String = ""
    var errorMessage: String? = nil
}

@MainActor
final class AddLogViewModel: ObservableObject {
    @Published var entryMode: LogEntryMode = .description
    @Published var descriptionText: String = ""
    @Published var items: [FoodItemDraft] = [FoodItemDraft()]
    @Published var selectedItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    @Published var estimate: MacroEstimate? = nil
    @Published var caloriesText: String = ""
    @Published var proteinText: String = ""
    @Published var carbsText: String = ""
    @Published var fatText: String = ""
    @Published var isAnalyzing: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String? = nil
    @Published var analysisStage: AnalysisStage = .idle
    @Published var streamPreview: String = ""
    @Published var isLabelPhoto: Bool = false
    @Published var labelGramsText: String = ""
    @Published var savedFoods: [SavedFood] = []
    @Published var savedFoodStates: [UUID: SavedFoodQuickState] = [:]
    @Published var isSavedFoodsLoading: Bool = false
    @Published var savedFoodsError: String? = nil
    @Published var savedFoodsSelectionError: String? = nil
    @Published var searchText: String = ""
    @Published var filteredLibraryFoods: [SavedFood] = []
    @Published var isSearchPending: Bool = false
    @Published var selectedLibraryFood: SavedFood? = nil
    @Published var libraryFoodQuantityText: String = ""
    @Published var libraryCalculatedMacros: MacroDoubles? = nil
    @Published var showSaveToLibrary: Bool = false

    private var pendingEntryId: UUID? = nil
    private var pendingImagePath: String? = nil
    private var streamBuffer: String = ""
    private var searchDebounceTask: Task<Void, Never>? = nil
    private var labelBaseEstimate: MacroEstimate? = nil
    private var isApplyingLabelScale: Bool = false
    @Published private(set) var savedFoodsEstimateActive: Bool = false
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

    var canAnalyze: Bool {
        if selectedSavedFoodCount > 0 || savedFoodsEstimateActive {
            return !isAnalyzing
        }
        let hasText = hasTextInput
        let hasPhoto = selectedImageData != nil || pendingImagePath != nil
        return !isAnalyzing && (hasText || hasPhoto)
    }

    var isLibrarySelectionActive: Bool {
        selectedLibraryFood != nil
    }

    func loadSelectedImage() async {
        guard let selectedItem else { return }
        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                pendingEntryId = nil
                pendingImagePath = nil
                isLabelPhoto = false
            }
        } catch {
            errorMessage = "Unable to load photo."
        }
    }

    func analyze() async {
        if selectedSavedFoodCount > 0 {
            _ = analyzeSavedFoodsSelection()
            return
        }
        if savedFoodsEstimateActive {
            return
        }
        isAnalyzing = true
        errorMessage = nil
        analysisStage = .preparing
        streamPreview = ""
        streamBuffer = ""
        estimate = nil
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        showSaveToLibrary = false
        defer { isAnalyzing = false }
        do {
            let itemInputs = validatedItemInputs(
                requireAtLeastOne: entryMode == .list && selectedImageData == nil && pendingImagePath == nil
            )
            guard let itemInputs else {
                analysisStage = .idle
                return
            }
            let description = entryMode == .description ? descriptionText : ""

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
                text: description,
                items: itemInputs.isEmpty ? nil : itemInputs,
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
                    caloriesText = formatMacro(result.calories)
                    proteinText = formatMacro(result.protein)
                    carbsText = formatMacro(result.carbs)
                    fatText = formatMacro(result.fat)
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
                    text: description,
                    items: itemInputs.isEmpty ? nil : itemInputs,
                    imagePath: pendingImagePath,
                    inputType: analysisInputType
                )
                estimate = fallback
                caloriesText = formatMacro(fallback.calories)
                proteinText = formatMacro(fallback.protein)
                carbsText = formatMacro(fallback.carbs)
                fatText = formatMacro(fallback.fat)
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

    func saveEntry() async -> Bool {
        if let selectedLibraryFood {
            return await saveLibrarySelection(selectedLibraryFood)
        }
        guard let calories = parseMacro(caloriesText),
              let protein = parseMacro(proteinText),
              let carbs = parseMacro(carbsText),
              let fat = parseMacro(fatText),
              let estimate = estimate else {
            errorMessage = "Please enter valid macros."
            return false
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

            let itemInputs = validatedItemInputs(requireAtLeastOne: entryMode == .list && imagePath == nil)
            guard let itemInputs else { return false }

            let entryItems = buildEntryItems(
                entryId: entryId,
                userId: userId,
                itemInputs: itemInputs,
                estimate: estimate
            )
            if entryMode == .list, !itemInputs.isEmpty, entryItems == nil {
                return false
            }

            let resolvedInputText = suggestedFoodName()
            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: activeDate,
                inputType: resolvedInputType.databaseValue,
                inputText: resolvedInputText.isEmpty ? nil : resolvedInputText,
                imagePath: imagePath,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                aiConfidence: estimate.confidence,
                aiSource: estimate.source,
                aiNotes: estimate.notes,
                createdAt: nil
            )

            try await entryRepository.insertFoodEntry(entry, items: entryItems ?? [])
            return true
        } catch {
            errorMessage = "Unable to save entry: \(error.localizedDescription)"
            return false
        }
    }

    func suggestedFoodName() -> String {
        if let selectedLibraryFood {
            return selectedLibraryFood.name
        }
        let itemNames = items
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !itemNames.isEmpty {
            return itemNames.joined(separator: " + ")
        }
        let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            return description
        }
        let aiName = estimate?.foodName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let aiName, !aiName.isEmpty {
            return aiName
        }
        return "Meal"
    }

    func validateLibraryName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Please enter a food name to save to Library."
            return false
        }
        return true
    }

    func buildLibraryDraft(name: String) -> SavedFoodDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a food name to save to Library."
            return nil
        }
        guard var calories = parseMacro(caloriesText),
              var protein = parseMacro(proteinText),
              var carbs = parseMacro(carbsText),
              var fat = parseMacro(fatText) else {
            errorMessage = "Please enter valid macro values."
            return nil
        }

        if isLabelPhoto, let grams = parseMacro(labelGramsText), grams > 0 {
            let multiplier = grams / 100.0
            if multiplier > 0 {
                calories = calories / multiplier
                protein = protein / multiplier
                carbs = carbs / multiplier
                fat = fat / multiplier
            }
        }

        return SavedFoodDraft(
            name: trimmed,
            unitType: .per100g,
            servingSize: nil,
            servingUnit: nil,
            caloriesPer100g: calories,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat,
            caloriesPerServing: 0,
            proteinPerServing: 0,
            carbsPerServing: 0,
            fatPerServing: 0
        )
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

    private func buildSavedFoodStates(for foods: [SavedFood]) -> [UUID: SavedFoodQuickState] {
        var nextState: [UUID: SavedFoodQuickState] = [:]
        for food in foods {
            if let existing = savedFoodStates[food.id] {
                nextState[food.id] = existing
            } else {
                nextState[food.id] = defaultSavedFoodState(for: food)
            }
        }
        return nextState
    }

    private func defaultSavedFoodState(for food: SavedFood) -> SavedFoodQuickState {
        SavedFoodQuickState(
            isActive: false,
            gramsText: "",
            errorMessage: nil
        )
    }

    private func invalidateSavedFoodsEstimate() {
        guard savedFoodsEstimateActive else { return }
        estimate = nil
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        savedFoodsEstimateActive = false
    }

    private func updateEstimateFromSavedFoods(using selections: [(food: SavedFood, quantity: Double)]) {
        let totals = selections.reduce(
            into: MacroDoubles(calories: 0, protein: 0, carbs: 0, fat: 0)
        ) { partial, item in
            let totals = item.food.macroDoubles(for: item.quantity)
            partial = MacroDoubles(
                calories: partial.calories + totals.calories,
                protein: partial.protein + totals.protein,
                carbs: partial.carbs + totals.carbs,
                fat: partial.fat + totals.fat
            )
        }

        let name = selections.map { $0.food.name }.joined(separator: " + ")
        estimate = MacroEstimate(
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            confidence: nil,
            source: "library",
            foodName: name,
            notes: "Saved foods",
            items: []
        )
        caloriesText = formatMacro(totals.calories)
        proteinText = formatMacro(totals.protein)
        carbsText = formatMacro(totals.carbs)
        fatText = formatMacro(totals.fat)
        entryMode = .description
        descriptionText = name
        items = [FoodItemDraft()]
        analysisStage = .idle
        streamPreview = ""
        streamBuffer = ""
        errorMessage = nil
        savedFoodsEstimateActive = true
        clearPhoto()
    }

    func saveLibraryDraft(_ draft: SavedFoodDraft) async -> LibrarySaveResult {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let existing = try await savedFoodRepository.fetchFoodByName(draft.name) {
                return .duplicate(existing: existing, draft: draft)
            }
            try await savedFoodRepository.insertFood(draft)
            return .saved
        } catch {
            errorMessage = "Unable to save to Library: \(error.localizedDescription)"
            return .failed
        }
    }

    func resolveLibraryDuplicate(
        choice: LibraryDuplicateChoice,
        existing: SavedFood,
        draft: SavedFoodDraft
    ) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            switch choice {
            case .updateExisting:
                try await savedFoodRepository.updateFood(id: existing.id, draft: draft)
            case .createNew:
                try await savedFoodRepository.insertFood(draft)
            }
            return true
        } catch {
            errorMessage = "Unable to save to Library: \(error.localizedDescription)"
            return false
        }
    }

    func reset() {
        entryMode = .description
        descriptionText = ""
        items = [FoodItemDraft()]
        selectedItem = nil
        selectedImageData = nil
        estimate = nil
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        pendingEntryId = nil
        pendingImagePath = nil
        isAnalyzing = false
        isSaving = false
        errorMessage = nil
        analysisStage = .idle
        streamPreview = ""
        streamBuffer = ""
        isLabelPhoto = false
        labelGramsText = ""
        labelBaseEstimate = nil
        savedFoodsError = nil
        savedFoodsSelectionError = nil
        savedFoodsEstimateActive = false
        savedFoodStates = buildSavedFoodStates(for: savedFoods)
        searchText = ""
        filteredLibraryFoods = []
        isSearchPending = false
        selectedLibraryFood = nil
        libraryFoodQuantityText = ""
        libraryCalculatedMacros = nil
        showSaveToLibrary = false
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

    func searchLibraryFoods(_ query: String) {
        searchDebounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filteredLibraryFoods = []
            isSearchPending = false
            return
        }

        isSearchPending = true
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            if savedFoods.isEmpty && !isSavedFoodsLoading {
                await loadSavedFoods()
            }
            let lowered = trimmed.lowercased()
            filteredLibraryFoods = savedFoods.filter { food in
                food.name.lowercased().contains(lowered)
            }
            isSearchPending = false
        }
    }

    func selectLibraryFood(_ food: SavedFood) {
        selectedLibraryFood = food
        searchText = ""
        filteredLibraryFoods = []
        isSearchPending = false
        libraryFoodQuantityText = ""
        libraryCalculatedMacros = nil
        descriptionText = ""
        items = [FoodItemDraft()]
        entryMode = .description
        estimate = nil
        showSaveToLibrary = false
        errorMessage = nil
    }

    func clearLibrarySelection() {
        selectedLibraryFood = nil
        libraryFoodQuantityText = ""
        libraryCalculatedMacros = nil
        estimate = nil
        showSaveToLibrary = false
        isSearchPending = false
    }

    func calculateLibraryMacros() {
        guard let selectedLibraryFood else {
            libraryCalculatedMacros = nil
            return
        }
        guard let quantity = parseMacro(libraryFoodQuantityText), quantity > 0 else {
            libraryCalculatedMacros = nil
            return
        }
        libraryCalculatedMacros = selectedLibraryFood.macroDoubles(for: quantity)
    }

    func analyzeQuickText() async {
        guard applySearchTextToInputs() else { return }
        searchText = ""
        filteredLibraryFoods = []
        isSearchPending = false
        selectedLibraryFood = nil
        showSaveToLibrary = false

        await analyze()
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

    func enableManualEntry() {
        estimate = MacroEstimate(
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            confidence: nil,
            source: "manual",
            foodName: nil,
            notes: "Manual entry",
            items: []
        )
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        showSaveToLibrary = true
        errorMessage = nil
        analysisStage = .idle
        streamPreview = ""
    }

    func addItemRow() {
        items.append(FoodItemDraft())
    }

    func removeItemRow(id: UUID) {
        items.removeAll { $0.id == id }
        if items.isEmpty {
            items = [FoodItemDraft()]
        }
    }

    func applySavedFood(_ selection: SavedFoodSelection) {
        let totals = selection.food.macroDoubles(for: selection.quantity)
        estimate = MacroEstimate(
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            confidence: nil,
            source: "library",
            foodName: selection.food.name,
            notes: "Saved food",
            items: []
        )
        caloriesText = formatMacro(totals.calories)
        proteinText = formatMacro(totals.protein)
        carbsText = formatMacro(totals.carbs)
        fatText = formatMacro(totals.fat)
        entryMode = .description
        descriptionText = selection.food.name
        items = [FoodItemDraft()]
        analysisStage = .idle
        streamPreview = ""
        streamBuffer = ""
        errorMessage = nil
        savedFoodsEstimateActive = true
        clearPhoto()
    }

    func loadSavedFoods() async {
        isSavedFoodsLoading = true
        savedFoodsError = nil
        defer { isSavedFoodsLoading = false }
        do {
            let foods = try await savedFoodRepository.fetchFoods()
            savedFoods = foods
            savedFoodStates = buildSavedFoodStates(for: foods)
        } catch {
            savedFoodsError = "Unable to load saved foods: \(error.localizedDescription)"
        }
    }

    func savedFoodState(for food: SavedFood) -> SavedFoodQuickState {
        savedFoodStates[food.id] ?? defaultSavedFoodState(for: food)
    }

    var selectedSavedFoodCount: Int {
        savedFoodStates.values.filter { $0.isActive }.count
    }

    var maxSavedFoodsAllowed: Int {
        5
    }

    var canAnalyzeSavedFoodsSelection: Bool {
        let activeFoods = savedFoods.filter { savedFoodState(for: $0).isActive }
        guard !activeFoods.isEmpty else { return false }
        return activeFoods.allSatisfy { food in
            guard let quantity = parseMacro(savedFoodState(for: food).gramsText) else { return false }
            return quantity > 0
        }
    }

    func toggleSavedFood(_ food: SavedFood) {
        var state = savedFoodState(for: food)
        if state.isActive {
            state.isActive = false
            state.errorMessage = nil
            state.gramsText = ""
            savedFoodStates[food.id] = state
            invalidateSavedFoodsEstimate()
            return
        }
        guard selectedSavedFoodCount < maxSavedFoodsAllowed else {
            savedFoodsSelectionError = "You can add up to \(maxSavedFoodsAllowed) items."
            return
        }
        state.isActive = true
        savedFoodsSelectionError = nil
        state.gramsText = ""
        savedFoodStates[food.id] = state
        invalidateSavedFoodsEstimate()
    }

    func updateSavedFoodQuantityText(_ food: SavedFood, text: String) {
        var state = savedFoodState(for: food)
        state.gramsText = text
        state.errorMessage = nil
        savedFoodsSelectionError = nil
        savedFoodStates[food.id] = state
        invalidateSavedFoodsEstimate()
    }

    func analyzeSavedFoodsSelection() -> Bool {
        savedFoodsSelectionError = nil
        let activeFoods = savedFoods.filter { savedFoodState(for: $0).isActive }
        guard !activeFoods.isEmpty else {
            savedFoodsSelectionError = "Select at least one saved food."
            return false
        }

        var selections: [(food: SavedFood, quantity: Double)] = []
        for food in activeFoods {
            var state = savedFoodState(for: food)
            guard let quantity = parseMacro(state.gramsText), quantity > 0 else {
                state.errorMessage = "Enter grams."
                savedFoodStates[food.id] = state
                continue
            }
            state.errorMessage = nil
            savedFoodStates[food.id] = state
            selections.append((food: food, quantity: quantity))
        }

        guard selections.count == activeFoods.count else {
            savedFoodsSelectionError = "Please fix grams for selected items."
            return false
        }

        updateEstimateFromSavedFoods(using: selections)
        return true
    }

    private func saveLibrarySelection(_ food: SavedFood) async -> Bool {
        guard let quantity = parseMacro(libraryFoodQuantityText), quantity > 0 else {
            errorMessage = "Please enter a valid quantity."
            return false
        }
        let macros = food.macroDoubles(for: quantity)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let entryId = UUID()
            let activeDate = try await resolvedActiveDate(for: userId)
            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: activeDate,
                inputType: LogInputType.text.databaseValue,
                inputText: food.name,
                imagePath: nil,
                calories: macros.calories,
                protein: macros.protein,
                carbs: macros.carbs,
                fat: macros.fat,
                aiConfidence: nil,
                aiSource: "library",
                aiNotes: "From saved library",
                createdAt: nil
            )

            try await entryRepository.insertFoodEntry(entry, items: [])
            return true
        } catch {
            errorMessage = "Unable to save entry: \(error.localizedDescription)"
            return false
        }
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

    private var analysisInputType: String {
        if isLabelPhoto, selectedImageData != nil || pendingImagePath != nil {
            return "label_photo"
        }
        return resolvedInputType.databaseValue
    }

    private var resolvedInputType: LogInputType {
        let hasText = hasTextInput
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

        guard shouldParseStreamTotals, let partial = parsePartialEstimate(from: streamBuffer) else {
            return
        }
        if let calories = partial.calories {
            caloriesText = formatMacro(calories)
        }
        if let protein = partial.protein {
            proteinText = formatMacro(protein)
        }
        if let carbs = partial.carbs {
            carbsText = formatMacro(carbs)
        }
        if let fat = partial.fat {
            fatText = formatMacro(fat)
        }
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

    private func parsePartialEstimate(from text: String) -> PartialEstimate? {
        PartialEstimate(
            calories: extractNumber(for: "calories", in: text),
            protein: extractNumber(for: "protein", in: text),
            carbs: extractNumber(for: "carbs", in: text),
            fat: extractNumber(for: "fat", in: text)
        )
    }

    private func extractNumber(for key: String, in text: String) -> Double? {
        let pattern = "\"\(key)\"\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[valueRange])
    }

    private var hasTextInput: Bool {
        switch entryMode {
        case .list:
            return hasItemInput
        case .description:
            let hasDescription = !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSearchText = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasDescription || hasSearchText
        }
    }

    private var hasItemInput: Bool {
        items.contains { draft in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let grams = draft.gramsText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty || !grams.isEmpty
        }
    }

    private var shouldParseStreamTotals: Bool {
        switch entryMode {
        case .list:
            return !hasItemInput
        case .description:
            return true
        }
    }

    private func validatedItemInputs(requireAtLeastOne: Bool) -> [AIItemInput]? {
        guard entryMode == .list else { return [] }
        var inputs: [AIItemInput] = []

        for draft in items {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let gramsText = draft.gramsText.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty && gramsText.isEmpty {
                continue
            }
            guard !name.isEmpty else {
                errorMessage = "Please enter a food name for each item."
                return nil
            }
            guard let grams = parseMacro(gramsText), grams > 0 else {
                errorMessage = "Please enter grams for each item."
                return nil
            }
            inputs.append(AIItemInput(name: name, grams: grams))
        }

        if requireAtLeastOne && inputs.isEmpty {
            errorMessage = "Add at least one food item or attach a photo."
            return nil
        }

        return inputs
    }

    private func parseQuickTextFormat(_ text: String) -> (name: String, grams: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns: [(pattern: String, nameIndex: Int, gramsIndex: Int)] = [
            (#"^(.+?)\s+(\d+(?:\.\d+)?)\s*g?$"#, 1, 2),
            (#"^(\d+(?:\.\d+)?)\s*g?\s+(.+)$"#, 2, 1)
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range) else { continue }
            guard let nameRange = Range(match.range(at: pattern.nameIndex), in: trimmed),
                  let gramsRange = Range(match.range(at: pattern.gramsIndex), in: trimmed) else {
                continue
            }
            let name = String(trimmed[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let gramsText = String(trimmed[gramsRange])
            guard let grams = Double(gramsText), grams > 0 else { continue }
            guard !name.isEmpty else { continue }
            return (name: name, grams: grams)
        }

        return nil
    }

    private func estimateFromCurrentFields() -> MacroEstimate? {
        guard let calories = parseMacro(caloriesText),
              let protein = parseMacro(proteinText),
              let carbs = parseMacro(carbsText),
              let fat = parseMacro(fatText) else {
            return nil
        }
        return MacroEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: estimate?.confidence,
            source: estimate?.source ?? "manual",
            foodName: estimate?.foodName,
            notes: estimate?.notes ?? "",
            items: estimate?.items ?? []
        )
    }

    private func updateEstimateFromBase(_ base: MacroEstimate) {
        estimate = base
        caloriesText = formatMacro(base.calories)
        proteinText = formatMacro(base.protein)
        carbsText = formatMacro(base.carbs)
        fatText = formatMacro(base.fat)
    }

    @discardableResult
    func applySearchTextToInputs() -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }

        if let parsed = parseQuickTextFormat(query) {
            entryMode = .list
            items = [FoodItemDraft(name: parsed.name, gramsText: formatMacro(parsed.grams))]
            descriptionText = ""
        } else {
            entryMode = .description
            descriptionText = query
        }
        return true
    }

    private func buildEntryItems(
        entryId: UUID,
        userId: UUID,
        itemInputs: [AIItemInput],
        estimate: MacroEstimate
    ) -> [FoodEntryItem]? {
        // For list mode: match user inputs with AI results
        if !itemInputs.isEmpty {
            guard !estimate.items.isEmpty else {
                errorMessage = "Please run analysis to estimate each item."
                return nil
            }
            guard estimate.items.count == itemInputs.count else {
                errorMessage = "AI returned a different number of items. Please try again."
                return nil
            }

            return zip(itemInputs, estimate.items).map { input, result in
                FoodEntryItem(
                    id: UUID(),
                    entryId: entryId,
                    userId: userId,
                    name: input.name,
                    grams: input.grams,
                    calories: result.calories,
                    protein: result.protein,
                    carbs: result.carbs,
                    fat: result.fat,
                    aiConfidence: result.confidence,
                    aiNotes: result.notes ?? "",
                    createdAt: nil
                )
            }
        }

        // For description/photo mode: use AI-provided items directly
        guard !estimate.items.isEmpty else { return [] }

        return estimate.items.map { item in
            FoodEntryItem(
                id: UUID(),
                entryId: entryId,
                userId: userId,
                name: item.name,
                grams: item.grams,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                aiConfidence: item.confidence,
                aiNotes: item.notes ?? "",
                createdAt: nil
            )
        }
    }
}

enum LibrarySaveResult {
    case saved
    case duplicate(existing: SavedFood, draft: SavedFoodDraft)
    case failed
}

enum LibraryDuplicateChoice {
    case updateExisting
    case createNew
}

struct PartialEstimate {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

enum AnalysisStage: String {
    case idle
    case preparing
    case uploading
    case requestingModel
    case streaming
    case finalizing

    init(from stage: String) {
        switch stage {
        case "uploading":
            self = .uploading
        case "requesting_model":
            self = .requestingModel
        case "streaming":
            self = .streaming
        case "finalizing":
            self = .finalizing
        default:
            self = .preparing
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing input"
        case .uploading:
            return "Uploading photo"
        case .requestingModel:
            return "Estimating macros"
        case .streaming:
            return "Streaming insights"
        case .finalizing:
            return "Finalizing"
        }
    }
}
