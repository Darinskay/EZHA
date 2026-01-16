import Foundation

struct FoodEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var inputType: LogInputType
    var inputText: String
    var imageData: Data?
    var aiConfidence: Double
    var aiSource: String

    init(
        id: UUID = UUID(),
        date: Date,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        inputType: LogInputType,
        inputText: String,
        imageData: Data?,
        aiConfidence: Double,
        aiSource: String
    ) {
        self.id = id
        self.date = date
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.inputType = inputType
        self.inputText = inputText
        self.imageData = imageData
        self.aiConfidence = aiConfidence
        self.aiSource = aiSource
    }
}

struct MacroTotals: Hashable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0)
}

struct MacroTargets: Hashable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    static let example = MacroTargets(calories: 2100, protein: 140, carbs: 220, fat: 70)
}

enum LogInputType: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case text = "Text"
    case photoText = "Photo + Text"

    var id: String { rawValue }
}

struct MacroEstimate: Hashable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var confidence: Double
    var source: String
}
