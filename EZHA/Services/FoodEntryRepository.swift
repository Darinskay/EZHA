import Foundation
import Supabase

struct FoodEntryRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func insertFoodEntry(_ entry: FoodEntry, items: [FoodEntryItem] = []) async throws {
        var payload = entry
        let userId = try await currentUserId()
        payload.userId = userId
        try await supabase
            .from("food_entries")
            .insert(payload)
            .execute()

        guard !items.isEmpty else { return }
        let itemPayloads = items.map { item -> FoodEntryItem in
            var updated = item
            updated.userId = userId
            updated.entryId = entry.id
            return updated
        }
        do {
            try await supabase
                .from("food_entry_items")
                .insert(itemPayloads)
                .execute()
        } catch {
            _ = try? await supabase
                .from("food_entries")
                .delete()
                .eq("id", value: entry.id.uuidString)
                .execute()
            throw error
        }
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

    func fetchItems(for entryId: UUID) async throws -> [FoodEntryItem] {
        try await supabase
            .from("food_entry_items")
            .select()
            .eq("entry_id", value: entryId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchEntriesWithItems(for date: Date, timeZone: TimeZone) async throws -> [FoodEntryWithItems] {
        let entries = try await fetchEntries(for: date, timeZone: timeZone)
        return try await fetchItemsForEntries(entries)
    }

    func fetchEntriesWithItems(from startDate: Date, to endDate: Date, timeZone: TimeZone) async throws -> [FoodEntryWithItems] {
        let entries = try await fetchEntries(from: startDate, to: endDate, timeZone: timeZone)
        return try await fetchItemsForEntries(entries)
    }

    private func fetchItemsForEntries(_ entries: [FoodEntry]) async throws -> [FoodEntryWithItems] {
        guard !entries.isEmpty else { return [] }

        let entryIds = entries.map { $0.id.uuidString }
        let allItems: [FoodEntryItem] = try await supabase
            .from("food_entry_items")
            .select()
            .in("entry_id", values: entryIds)
            .order("created_at", ascending: true)
            .execute()
            .value

        let itemsByEntryId = Dictionary(grouping: allItems) { $0.entryId }

        return entries.map { entry in
            FoodEntryWithItems(
                entry: entry,
                items: itemsByEntryId[entry.id] ?? []
            )
        }
    }

    private func currentUserId() async throws -> UUID {
        try await SupabaseConfig.currentUserId()
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
