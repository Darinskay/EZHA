import Foundation
import Supabase

struct FoodEntryRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func insertFoodEntry(_ entry: FoodEntry) async throws {
        var payload = entry
        payload.userId = try await currentUserId()
        try await supabase
            .from("food_entries")
            .insert(payload)
            .execute()
    }

    func fetchEntries(for date: Date, timeZone: TimeZone) async throws -> [FoodEntry] {
        let dateString = dateFormatter(timeZone: timeZone).string(from: date)
        return try await supabase
            .from("food_entries")
            .select()
            .eq("date", value: dateString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchEntries(from startDate: Date, to endDate: Date, timeZone: TimeZone) async throws -> [FoodEntry] {
        let formatter = dateFormatter(timeZone: timeZone)
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        return try await supabase
            .from("food_entries")
            .select()
            .gte("date", value: startString)
            .lte("date", value: endString)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func deleteEntry(id: UUID) async throws {
        try await supabase
            .from("food_entries")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    private func currentUserId() async throws -> UUID {
        try await supabase.auth.session.user.id
    }

    private func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
