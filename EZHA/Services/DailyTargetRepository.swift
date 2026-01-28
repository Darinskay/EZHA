import Foundation
import Supabase

struct DailyTargetRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func fetchTargets() async throws -> [DailyTarget] {
        let userId = try await currentUserId()
        return try await supabase
            .from("daily_targets")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func insertTarget(
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async throws {
        var payload = DailyTargetPayload(
            name: name,
            caloriesTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat
        )
        payload.userId = try await currentUserId()
        try await supabase
            .from("daily_targets")
            .insert(payload)
            .execute()
    }

    func updateTarget(
        id: UUID,
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async throws {
        let payload = DailyTargetPayload(
            name: name,
            caloriesTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat
        )
        try await supabase
            .from("daily_targets")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteTarget(id: UUID) async throws {
        try await supabase
            .from("daily_targets")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func ensureTargets(for profile: Profile) async throws -> [DailyTarget] {
        let existing = try await fetchTargets()
        if !existing.isEmpty {
            return existing
        }
        try await insertTarget(
            name: "Basic",
            calories: profile.caloriesTarget,
            protein: profile.proteinTarget,
            carbs: profile.carbsTarget,
            fat: profile.fatTarget
        )
        return try await fetchTargets()
    }

    func fetchTarget(id: UUID) async throws -> DailyTarget? {
        let targets: [DailyTarget] = try await supabase
            .from("daily_targets")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return targets.first
    }

    private func currentUserId() async throws -> UUID {
        try await SupabaseConfig.currentUserId()
    }
}

private struct DailyTargetPayload: Codable {
    var userId: UUID?
    var name: String
    var caloriesTarget: Double
    var proteinTarget: Double
    var carbsTarget: Double
    var fatTarget: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case caloriesTarget = "calories_target"
        case proteinTarget = "protein_target"
        case carbsTarget = "carbs_target"
        case fatTarget = "fat_target"
    }
}
