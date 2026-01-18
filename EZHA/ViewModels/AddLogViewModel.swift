import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class AddLogViewModel: ObservableObject {
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

    private var pendingEntryId: UUID? = nil
    private var pendingImagePath: String? = nil
    private let analysisService: AIAnalysisService
    private let entryRepository: FoodEntryRepository
    private let profileRepository: ProfileRepository
    private let storageService: StorageService

    init(
        analysisService: AIAnalysisService = AIAnalysisService(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        profileRepository: ProfileRepository = ProfileRepository(),
        storageService: StorageService = StorageService()
    ) {
        self.analysisService = analysisService
        self.entryRepository = entryRepository
        self.profileRepository = profileRepository
        self.storageService = storageService
    }

    var canAnalyze: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = selectedImageData != nil
        return !isAnalyzing && (hasText || hasPhoto)
    }

    func loadSelectedImage() async {
        guard let selectedItem else { return }
        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                selectedImageData = data
                pendingEntryId = nil
                pendingImagePath = nil
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
            if let imageData = selectedImageData, pendingImagePath == nil {
                let userId = try await SupabaseConfig.client.auth.session.user.id
                let entryId = pendingEntryId ?? UUID()
                pendingEntryId = entryId
                pendingImagePath = try await storageService.uploadFoodImage(
                    data: imageData,
                    userId: userId,
                    entryId: entryId
                )
            }

            let result = try await analysisService.analyze(
                text: inputText,
                imagePath: pendingImagePath,
                inputType: analysisInputType
            )
            estimate = result
            caloriesText = String(result.calories)
            proteinText = String(result.protein)
            carbsText = String(result.carbs)
            fatText = String(result.fat)
        } catch {
            errorMessage = error.localizedDescription
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

            let entry = FoodEntry(
                id: entryId,
                userId: userId,
                date: activeDate,
                inputType: resolvedInputType.databaseValue,
                inputText: inputText.isEmpty ? nil : inputText,
                imagePath: imagePath,
                calories: Double(calories),
                protein: Double(protein),
                carbs: Double(carbs),
                fat: Double(fat),
                aiConfidence: estimate.confidence,
                aiSource: estimate.source,
                aiNotes: estimate.notes,
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
        inputText = ""
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
        resolvedInputType.databaseValue
    }

    private var resolvedInputType: LogInputType {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
}
