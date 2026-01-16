import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dailyTotals: [(date: Date, totals: MacroTotals)] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let daysToShow: Int = 60
    private let entryRepository: FoodEntryRepository

    init(entryRepository: FoodEntryRepository = FoodEntryRepository()) {
        self.entryRepository = entryRepository
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let endDate = calendar.startOfDay(for: Date())
            guard let startDate = calendar.date(byAdding: .day, value: -(daysToShow - 1), to: endDate) else {
                dailyTotals = []
                return
            }

            let entries = try await entryRepository.fetchEntries(
                from: startDate,
                to: endDate,
                timeZone: TimeZone.current
            )
            dailyTotals = Self.groupedTotals(entries: entries, from: startDate, to: endDate)
        } catch {
            errorMessage = "Unable to load history."
        }
    }

    private static func groupedTotals(
        entries: [FoodEntry],
        from startDate: Date,
        to endDate: Date
    ) -> [(date: Date, totals: MacroTotals)] {
        let calendar = Calendar.current
        var grouped: [Date: MacroTotals] = [:]

        for entry in entries {
            guard let entryDate = dateFromString(entry.date) else { continue }
            let totals = grouped[entryDate] ?? .zero
            grouped[entryDate] = MacroTotals(
                calories: totals.calories + Int(entry.calories),
                protein: totals.protein + Int(entry.protein),
                carbs: totals.carbs + Int(entry.carbs),
                fat: totals.fat + Int(entry.fat)
            )
        }

        var results: [(date: Date, totals: MacroTotals)] = []
        var day = startDate
        while day <= endDate {
            let dayTotals = grouped[day] ?? .zero
            results.append((day, dayTotals))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return results.reversed()
    }

    private static func dateFromString(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
