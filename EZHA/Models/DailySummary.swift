import Foundation

struct DailySummary: Codable, Hashable {
    var userId: UUID
    var date: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var caloriesTarget: Double
    var proteinTarget: Double
    var carbsTarget: Double
    var fatTarget: Double
    var hasData: Bool
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case calories
        case protein
        case carbs
        case fat
        case caloriesTarget = "calories_target"
        case proteinTarget = "protein_target"
        case carbsTarget = "carbs_target"
        case fatTarget = "fat_target"
        case hasData = "has_data"
        case createdAt = "created_at"
    }
}
