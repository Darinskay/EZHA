import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dailySummaries: [DailySummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let daysToShow: Int = 60
    private let summaryRepository: DailySummaryRepository
    private let profileRepository: ProfileRepository

    init(
        summaryRepository: DailySummaryRepository = DailySummaryRepository(),
        profileRepository: ProfileRepository = ProfileRepository()
    ) {
        self.summaryRepository = summaryRepository
        self.profileRepository = profileRepository
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
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

    private static func mergeSummaries(
        summaries: [DailySummary],
        startDate: Date,
        endDate: Date
    ) -> [DailySummary] {
        let calendar = Calendar.current
        var summaryByDate: [String: DailySummary] = [:]
        for summary in summaries {
            summaryByDate[summary.date] = summary
        }
        let fallbackUserId = summaries.first?.userId ?? UUID()

        var results: [DailySummary] = []
        var day = startDate
        while day <= endDate {
            let dateString = dateFormatter.string(from: day)
            if let summary = summaryByDate[dateString] {
                results.append(summary)
            } else {
                results.append(
                    DailySummary(
                        userId: fallbackUserId,
                        date: dateString,
                        calories: 0,
                        protein: 0,
                        carbs: 0,
                        fat: 0,
                        caloriesTarget: 0,
                        proteinTarget: 0,
                        carbsTarget: 0,
                        fatTarget: 0,
                        hasData: false,
                        createdAt: nil
                    )
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return results.reversed()
    }

    private static func dateFromString(_ value: String) -> Date? {
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
