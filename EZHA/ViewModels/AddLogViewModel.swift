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
    @Published var entryMode: LogEntryMode = .list
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
    @Published var savedFoods: [SavedFood] = []
    @Published var savedFoodStates: [UUID: SavedFoodQuickState] = [:]
    @Published var isSavedFoodsLoading: Bool = false
    @Published var savedFoodsError: String? = nil
    @Published var savedFoodsSelectionError: String? = nil

    private var pendingEntryId: UUID? = nil
    private var pendingImagePath: String? = nil
    private var streamBuffer: String = ""
    private var savedFoodsEstimateActive: Bool = false
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
        let hasText = hasTextInput
        let hasPhoto = selectedImageData != nil || pendingImagePath != nil
        return !isAnalyzing && (hasText || hasPhoto)
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
            }
        } catch {
            errorMessage = error.localizedDescription
            analysisStage = .idle
        }
    }

    func saveEntry() async -> Bool {
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
        guard let calories = parseMacro(caloriesText),
              let protein = parseMacro(proteinText),
              let carbs = parseMacro(carbsText),
              let fat = parseMacro(fatText) else {
            errorMessage = "Please enter valid macro values."
            return nil
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
        let totals = selections.reduce(into: MacroTotals.zero) { partial, item in
            let totals = item.food.macros(for: item.quantity)
            partial.calories += totals.calories
            partial.protein += totals.protein
            partial.carbs += totals.carbs
            partial.fat += totals.fat
        }

        let name = selections.map { $0.food.name }.joined(separator: " + ")
        estimate = MacroEstimate(
            calories: Double(totals.calories),
            protein: Double(totals.protein),
            carbs: Double(totals.carbs),
            fat: Double(totals.fat),
            confidence: nil,
            source: "text",
            foodName: name,
            notes: "Saved foods",
            items: []
        )
        caloriesText = String(totals.calories)
        proteinText = String(totals.protein)
        carbsText = String(totals.carbs)
        fatText = String(totals.fat)
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
        entryMode = .list
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
        savedFoodsError = nil
        savedFoodsSelectionError = nil
        savedFoodsEstimateActive = false
        savedFoodStates = buildSavedFoodStates(for: savedFoods)
    }

    func clearPhoto() {
        selectedItem = nil
        selectedImageData = nil
        pendingEntryId = nil
        pendingImagePath = nil
        isLabelPhoto = false
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
        let totals = selection.food.macros(for: selection.quantity)
        estimate = MacroEstimate(
            calories: Double(totals.calories),
            protein: Double(totals.protein),
            carbs: Double(totals.carbs),
            fat: Double(totals.fat),
            confidence: nil,
            source: "text",
            foodName: selection.food.name,
            notes: "Saved food",
            items: []
        )
        caloriesText = String(totals.calories)
        proteinText = String(totals.protein)
        carbsText = String(totals.carbs)
        fatText = String(totals.fat)
        entryMode = .description
        descriptionText = selection.food.name
        items = [FoodItemDraft()]
        analysisStage = .idle
        streamPreview = ""
        streamBuffer = ""
        errorMessage = nil
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
            return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func buildEntryItems(
        entryId: UUID,
        userId: UUID,
        itemInputs: [AIItemInput],
        estimate: MacroEstimate
    ) -> [FoodEntryItem]? {
        guard !itemInputs.isEmpty else { return [] }
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
