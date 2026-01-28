import Foundation

struct DailyTarget: Identifiable, Codable, Hashable {
    var id: UUID
    var userId: UUID
    var name: String
    var caloriesTarget: Double
    var proteinTarget: Double
    var carbsTarget: Double
    var fatTarget: Double
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case caloriesTarget = "calories_target"
        case proteinTarget = "protein_target"
        case carbsTarget = "carbs_target"
        case fatTarget = "fat_target"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var macroTargets: MacroTargets {
        MacroTargets(
            calories: Int(round(caloriesTarget)),
            protein: Int(round(proteinTarget)),
            carbs: Int(round(carbsTarget)),
            fat: Int(round(fatTarget))
        )
    }
}

struct DailyTargetInput: Hashable {
    var id: UUID?
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}
