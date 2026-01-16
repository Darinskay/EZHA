import Foundation
import Supabase

struct ProfileRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func fetchProfile() async throws -> Profile? {
        let userId = try await currentUserId()
        do {
            return try await supabase
                .from("profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value
        } catch {
            return nil
        }
    }

    func upsertProfileTargets(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async throws {
        let userId = try await currentUserId()
        let payload = Profile(
            userId: userId,
            caloriesTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await supabase
            .from("profiles")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }

    func ensureProfileRowExists(defaultTargets: Profile) async throws {
        if let _ = try await fetchProfile() {
            return
        }
        try await supabase
            .from("profiles")
            .insert(defaultTargets)
            .execute()
    }

    private func currentUserId() async throws -> UUID {
        try await supabase.auth.session.user.id
    }
}
