import Foundation
import Supabase

struct SavedFoodRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func fetchFoods() async throws -> [SavedFood] {
        try await supabase
            .from("saved_foods")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchFoodByName(_ name: String) async throws -> SavedFood? {
        let userId = try await currentUserId()
        let foods: [SavedFood] = try await supabase
            .from("saved_foods")
            .select()
            .eq("user_id", value: userId.uuidString)
            .ilike("name", pattern: name)
            .limit(1)
            .execute()
            .value
        return foods.first
    }

    func insertFood(_ draft: SavedFoodDraft) async throws {
        var payload = SavedFoodPayload(from: draft)
        payload.userId = try await currentUserId()
        try await supabase
            .from("saved_foods")
            .insert(payload)
            .execute()
    }

    func updateFood(id: UUID, draft: SavedFoodDraft) async throws {
        let payload = SavedFoodPayload(from: draft)
        try await supabase
            .from("saved_foods")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteFood(id: UUID) async throws {
        try await supabase
            .from("saved_foods")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    private func currentUserId() async throws -> UUID {
        try await SupabaseConfig.currentUserId()
    }
}

private struct SavedFoodPayload: Codable {
    var userId: UUID?
    var name: String
    var unitType: String
    var servingSize: Double?
    var servingUnit: String?
    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var caloriesPerServing: Double
    var proteinPerServing: Double
    var carbsPerServing: Double
    var fatPerServing: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case unitType = "unit_type"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case caloriesPer100g = "calories_per_100g"
        case proteinPer100g = "protein_per_100g"
        case carbsPer100g = "carbs_per_100g"
        case fatPer100g = "fat_per_100g"
        case caloriesPerServing = "calories_per_serving"
        case proteinPerServing = "protein_per_serving"
        case carbsPerServing = "carbs_per_serving"
        case fatPerServing = "fat_per_serving"
    }

    init(from draft: SavedFoodDraft) {
        self.userId = nil
        self.name = draft.name
        self.unitType = draft.unitType.rawValue
        self.servingSize = draft.servingSize
        self.servingUnit = draft.servingUnit
        self.caloriesPer100g = draft.caloriesPer100g
        self.proteinPer100g = draft.proteinPer100g
        self.carbsPer100g = draft.carbsPer100g
        self.fatPer100g = draft.fatPer100g
        self.caloriesPerServing = draft.caloriesPerServing
        self.proteinPerServing = draft.proteinPerServing
        self.carbsPerServing = draft.carbsPerServing
        self.fatPerServing = draft.fatPerServing
    }
}
