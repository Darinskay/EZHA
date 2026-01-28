import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dailySummaries: [DailySummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var entriesWithItemsByDate: [String: [FoodEntryWithItems]] = [:]
    @Published private(set) var loadingDates: Set<String> = []
    @Published private(set) var entryErrors: [String: String] = [:]

    /// Convenience accessor for just entries (without items) - for backward compatibility
    var entriesByDate: [String: [FoodEntry]] {
        entriesWithItemsByDate.mapValues { $0.map { $0.entry } }
    }

    let daysToShow: Int = 60
    private let summaryRepository: DailySummaryRepository
    private let profileRepository: ProfileRepository
    private let entryRepository: FoodEntryRepository

    init(
        summaryRepository: DailySummaryRepository = DailySummaryRepository(),
        profileRepository: ProfileRepository = ProfileRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository()
    ) {
        self.summaryRepository = summaryRepository
        self.profileRepository = profileRepository
        self.entryRepository = entryRepository
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entriesWithItemsByDate = [:]
            loadingDates = []
            entryErrors = [:]
            guard let profile = try await profileRepository.fetchProfile() else {
                dailySummaries = []
                return
            }
            let endDate = Self.dateFromString(profile.activeDate)
            let end = Calendar.current.date(byAdding: .day, value: -1, to: endDate ?? Date()) ?? Date()
            guard let start = Calendar.current.date(byAdding: .day, value: -(daysToShow - 1), to: end) else {
                dailySummaries = []
                return
            }
            let startString = Self.dateFormatter.string(from: start)
            let endString = Self.dateFormatter.string(from: end)
            let summaries = try await summaryRepository.fetchSummaries(
                from: startString,
                to: endString
            )
            dailySummaries = Self.mergeSummaries(
                summaries: summaries,
                startDate: start,
                endDate: end
            )
        } catch {
            errorMessage = "Unable to load history."
        }
    }

    func loadEntries(for dateString: String) async {
        if entriesWithItemsByDate[dateString] != nil || loadingDates.contains(dateString) {
            return
        }
        loadingDates.insert(dateString)
        entryErrors[dateString] = nil
        defer { loadingDates.remove(dateString) }

        guard let date = Self.dateFromString(dateString) else {
            entryErrors[dateString] = "Unable to read this date."
            entriesWithItemsByDate[dateString] = []
            return
        }

        do {
            let entriesWithItems = try await entryRepository.fetchEntriesWithItems(
                for: date,
                timeZone: TimeZone.current
            )
            entriesWithItemsByDate[dateString] = entriesWithItems
        } catch {
            entryErrors[dateString] = "Unable to load entries."
            entriesWithItemsByDate[dateString] = []
        }
    }

    private static func mergeSummaries(
        summaries: [DailySummary],
        startDate: Date,
        endDate: Date
    ) -> [DailySummary] {
        summaries
            .filter { $0.hasData }
            .sorted { $0.date > $1.date }
    }

    static func dateFromString(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }

    func dateLabel(from value: String) -> String {
        guard let date = Self.dateFromString(value) else { return value }
        return Self.displayFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
