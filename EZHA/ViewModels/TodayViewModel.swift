import Foundation
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var targets: MacroTargets = .example
    @Published private(set) var totals: MacroTotals = .zero
    @Published private(set) var activeDate: String = ""
    @Published private(set) var entries: [FoodEntry] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let profileRepository: ProfileRepository
    private let entryRepository: FoodEntryRepository
    private let summaryRepository: DailySummaryRepository

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        summaryRepository: DailySummaryRepository = DailySummaryRepository()
    ) {
        self.profileRepository = profileRepository
        self.entryRepository = entryRepository
        self.summaryRepository = summaryRepository
    }

    func loadToday() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let userId = try await SupabaseConfig.client.auth.session.user.id
            let defaultProfile = Profile.defaultTargets(
                for: userId,
                activeDate: Self.dateFormatter.string(from: Date())
            )
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            if let profile = try await profileRepository.fetchProfile() {
                targets = MacroTargets(
                    calories: Int(profile.caloriesTarget),
                    protein: Int(profile.proteinTarget),
                    carbs: Int(profile.carbsTarget),
                    fat: Int(profile.fatTarget)
                )
                activeDate = profile.activeDate
            }

            let entries = try await entryRepository.fetchEntries(
                for: dateFromString(activeDate) ?? Date(),
                timeZone: TimeZone.current
            )
            self.entries = entries
            totals = Self.totals(from: entries)
        } catch {
            errorMessage = "Unable to load today's data."
        }
    }

    func startNewDay() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let profile = try await profileRepository.fetchProfile() else {
                errorMessage = "Unable to load profile."
                return
            }

            let entries = try await entryRepository.fetchEntries(
                for: dateFromString(profile.activeDate) ?? Date(),
                timeZone: TimeZone.current
            )
            let totals = Self.totals(from: entries)
            let summary = DailySummary(
                userId: profile.userId,
                date: profile.activeDate,
                calories: Double(totals.calories),
                protein: Double(totals.protein),
                carbs: Double(totals.carbs),
                fat: Double(totals.fat),
                caloriesTarget: profile.caloriesTarget,
                proteinTarget: profile.proteinTarget,
                carbsTarget: profile.carbsTarget,
                fatTarget: profile.fatTarget,
                hasData: !entries.isEmpty,
                createdAt: nil
            )
            try await summaryRepository.upsertSummary(summary)

            let nextDate = nextDayString(from: profile.activeDate)
            try await profileRepository.updateActiveDate(nextDate)
            activeDate = nextDate
            self.entries = []
            self.totals = .zero
        } catch {
            errorMessage = "Unable to start a new day."
        }
    }

    func deleteEntry(id: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await entryRepository.deleteEntry(id: id)
            await loadToday()
        } catch {
            errorMessage = "Unable to delete entry."
        }
    }

    private static func totals(from entries: [FoodEntry]) -> MacroTotals {
        MacroTotals(
            calories: Int(entries.reduce(0) { $0 + $1.calories }),
            protein: Int(entries.reduce(0) { $0 + $1.protein }),
            carbs: Int(entries.reduce(0) { $0 + $1.carbs }),
            fat: Int(entries.reduce(0) { $0 + $1.fat })
        )
    }

    private func nextDayString(from dateString: String) -> String {
        let date = dateFromString(dateString) ?? Date()
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? Date()
        return Self.dateFormatter.string(from: nextDate)
    }

    private func dateFromString(_ value: String) -> Date? {
        Self.dateFormatter.date(from: value)
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
