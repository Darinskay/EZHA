import Foundation
import Supabase

struct DailySummaryRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func upsertSummary(_ summary: DailySummary) async throws {
        try await supabase
            .from("daily_summaries")
            .upsert(summary, onConflict: "user_id,date")
            .execute()
    }

    func fetchSummaries(from startDate: String, to endDate: String) async throws -> [DailySummary] {
        try await supabase
            .from("daily_summaries")
            .select()
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date", ascending: false)
            .execute()
            .value
    }

    func fetchSummary(for date: String) async throws -> DailySummary? {
        let summaries: [DailySummary] = try await supabase
            .from("daily_summaries")
            .select()
            .eq("date", value: date)
            .limit(1)
            .execute()
            .value
        return summaries.first
    }
}
