import Foundation

struct FoodEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var userId: UUID
    var date: String
    var inputType: String
    var inputText: String?
    var imagePath: String?
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var aiConfidence: Double?
    var aiSource: String
    var aiNotes: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case inputType = "input_type"
        case inputText = "input_text"
        case imagePath = "image_path"
        case calories
        case protein
        case carbs
        case fat
        case aiConfidence = "ai_confidence"
        case aiSource = "ai_source"
        case aiNotes = "ai_notes"
        case createdAt = "created_at"
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

    var databaseValue: String {
        switch self {
        case .photo:
            return "photo"
        case .text:
            return "text"
        case .photoText:
            return "photo+text"
        }
    }
}

struct MacroEstimate: Hashable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var confidence: Double
    var source: String
}
