import Foundation

final class AIAnalysisService {
    func analyze(text: String, hasPhoto: Bool) async throws -> MacroEstimate {
        try await Task.sleep(nanoseconds: 800_000_000)
        let baseCalories = max(200, min(1200, text.count * 8))
        let adjustment = hasPhoto ? 120 : 0
        let calories = baseCalories + adjustment
        let protein = max(10, calories / 20)
        let carbs = max(20, calories / 8)
        let fat = max(5, calories / 35)
        return MacroEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: hasPhoto ? 0.72 : 0.63,
            source: hasPhoto ? "MockVisionAI" : "MockTextAI"
        )
    }
}
