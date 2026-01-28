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
        let existingProfile = try? await fetchProfile()
        let activeDate = existingProfile?.activeDate
            ?? Self.dateFormatter.string(from: Date())
        let activeTargetId = existingProfile?.activeTargetId
        let payload = Profile(
            userId: userId,
            caloriesTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat,
            activeDate: activeDate,
            activeTargetId: activeTargetId,
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

    func updateActiveDate(_ dateString: String) async throws {
        let userId = try await currentUserId()
        try await supabase
            .from("profiles")
            .update(["active_date": dateString])
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func updateActiveTarget(_ targetId: UUID) async throws {
        let userId = try await currentUserId()
        try await supabase
            .from("profiles")
            .update(["active_target_id": targetId.uuidString])
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func fetchActiveDate() async throws -> String {
        let userId = try await currentUserId()
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        return profile.activeDate
    }

    private func currentUserId() async throws -> UUID {
        try await SupabaseConfig.currentUserId()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
