import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class AddLogViewModel: ObservableObject {
    @Published var inputType: LogInputType = .text
    @Published var inputText: String = ""
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

    private let analysisService: AIAnalysisService
    private let entryRepository: FoodEntryRepository
    private let storageService: StorageService

    init(
        analysisService: AIAnalysisService = AIAnalysisService(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        storageService: StorageService = StorageService()
    ) {
        self.analysisService = analysisService
        self.entryRepository = entryRepository
        self.storageService = storageService
    }

    var isPhotoEnabled: Bool {
        inputType == .photo || inputType == .photoText
    }

    var isTextEnabled: Bool {
        inputType == .text || inputType == .photoText
    }

    func loadSelectedImage() async {
        guard let selectedItem else { return }
        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                selectedImageData = data
            }
        } catch {
            errorMessage = "Unable to load photo."
        }
    }

    func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            let result = try await analysisService.analyze(text: inputText, hasPhoto: selectedImageData != nil)
            estimate = result
            caloriesText = String(result.calories)
            proteinText = String(result.protein)
            carbsText = String(result.carbs)
            fatText = String(result.fat)
        } catch {
            errorMessage = "Analysis failed. Please try again."
        }
    }

    func saveEntry() async -> Bool {
        guard let calories = Int(caloriesText),
              let protein = Int(proteinText),
              let carbs = Int(carbsText),
              let fat = Int(fatText),
              let estimate = estimate else {
            errorMessage = "Please enter valid macros."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let userId = try await SupabaseConfig.client.auth.session.user.id
            let entryId = UUID()
            let dateString = Self.dateFormatter.string(from: Date())
            var imagePath: String?

            if let imageData = selectedImageData {
                imagePath = try await storageService.uploadFoodImage(
                    data: imageData,
                    userId: userId,
                    entryId: entryId
                )
            }

            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: dateString,
                inputType: inputType.databaseValue,
                inputText: inputText.isEmpty ? nil : inputText,
                imagePath: imagePath,
                calories: Double(calories),
                protein: Double(protein),
                carbs: Double(carbs),
                fat: Double(fat),
                aiConfidence: estimate.confidence,
                aiSource: aiSourceValue(for: inputType),
                aiNotes: estimate.source,
                createdAt: nil
            )

            try await entryRepository.insertFoodEntry(entry)
            return true
        } catch {
            errorMessage = "Unable to save entry: \(error.localizedDescription)"
            return false
        }
    }

    func reset() {
        inputType = .text
        inputText = ""
        selectedItem = nil
        selectedImageData = nil
        estimate = nil
        caloriesText = ""
        proteinText = ""
        carbsText = ""
        fatText = ""
        isAnalyzing = false
        isSaving = false
        errorMessage = nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func aiSourceValue(for inputType: LogInputType) -> String {
        switch inputType {
        case .text:
            return "text"
        case .photo, .photoText:
            return "food_photo"
        }
    }
}
