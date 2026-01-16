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
    @Published var errorMessage: String? = nil

    private let analysisService: AIAnalysisService

    init(analysisService: AIAnalysisService = AIAnalysisService()) {
        self.analysisService = analysisService
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

    func buildEntry() -> FoodEntry? {
        guard let calories = Int(caloriesText),
              let protein = Int(proteinText),
              let carbs = Int(carbsText),
              let fat = Int(fatText),
              let estimate = estimate else {
            return nil
        }

        return FoodEntry(
            date: Date(),
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            inputType: inputType,
            inputText: inputText,
            imageData: selectedImageData,
            aiConfidence: estimate.confidence,
            aiSource: estimate.source
        )
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
        errorMessage = nil
    }
}
