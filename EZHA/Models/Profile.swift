import Foundation

struct Profile: Codable, Hashable {
    var userId: UUID
    var caloriesTarget: Double
    var proteinTarget: Double
    var carbsTarget: Double
    var fatTarget: Double
    var activeDate: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case caloriesTarget = "calories_target"
        case proteinTarget = "protein_target"
        case carbsTarget = "carbs_target"
        case fatTarget = "fat_target"
        case activeDate = "active_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func defaultTargets(for userId: UUID, activeDate: String) -> Profile {
        Profile(
            userId: userId,
            caloriesTarget: 0,
            proteinTarget: 0,
            carbsTarget: 0,
            fatTarget: 0,
            activeDate: activeDate,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
