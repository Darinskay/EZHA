import Foundation
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var targets: MacroTargets = .example
    @Published private(set) var totals: MacroTotals = .zero
    @Published private(set) var activeDate: String = ""
    @Published private(set) var entriesWithItems: [FoodEntryWithItems] = []
    @Published private(set) var availableTargets: [DailyTarget] = []
    @Published private(set) var activeTarget: DailyTarget?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Convenience accessor for just the entries (without items)
    var entries: [FoodEntry] {
        entriesWithItems.map { $0.entry }
    }

    var title: String {
        guard let date = dateFromString(activeDate) else { return "Today" }
        let label = Self.titleFormatter.string(from: date)
        return "Today, \(label)"
    }

    private let profileRepository: ProfileRepository
    private let entryRepository: FoodEntryRepository
    private let summaryRepository: DailySummaryRepository
    private let targetRepository: DailyTargetRepository

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        summaryRepository: DailySummaryRepository = DailySummaryRepository(),
        targetRepository: DailyTargetRepository = DailyTargetRepository()
    ) {
        self.profileRepository = profileRepository
        self.entryRepository = entryRepository
        self.summaryRepository = summaryRepository
        self.targetRepository = targetRepository
    }

    func loadToday() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let defaultProfile = Profile.defaultTargets(
                for: userId,
                activeDate: Self.dateFormatter.string(from: Date())
            )
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            if let profile = try await profileRepository.fetchProfile() {
                availableTargets = try await targetRepository.ensureTargets(for: profile)
                let resolvedTarget = resolveActiveTarget(profile: profile, targets: availableTargets)
                activeTarget = resolvedTarget
                activeDate = profile.activeDate
                if let summary = try await summaryRepository.fetchSummary(for: activeDate) {
                    targets = MacroTargets(
                        calories: Int(round(summary.caloriesTarget)),
                        protein: Int(round(summary.proteinTarget)),
                        carbs: Int(round(summary.carbsTarget)),
                        fat: Int(round(summary.fatTarget))
                    )
                } else {
                    targets = resolvedTarget?.macroTargets ?? .example
                }
            }

            let entriesWithItems = try await entryRepository.fetchEntriesWithItems(
                for: dateFromString(activeDate) ?? Date(),
                timeZone: TimeZone.current
            )
            self.entriesWithItems = entriesWithItems
            totals = Self.totals(from: entriesWithItems.map { $0.entry })
        } catch {
            errorMessage = "Unable to load today's data."
        }
    }

    func startNewDay(nextTarget: DailyTarget) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let profile = try await profileRepository.fetchProfile() else {
                errorMessage = "Unable to load profile."
                return
            }
            let summaryForActiveDate = try await summaryRepository.fetchSummary(for: profile.activeDate)
            let currentTarget: DailyTarget?
            if let activeTarget {
                currentTarget = activeTarget
            } else if let activeTargetId = profile.activeTargetId {
                currentTarget = try await targetRepository.fetchTarget(id: activeTargetId)
            } else {
                currentTarget = nil
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
                caloriesTarget: summaryForActiveDate?.caloriesTarget ?? currentTarget?.caloriesTarget ?? profile.caloriesTarget,
                proteinTarget: summaryForActiveDate?.proteinTarget ?? currentTarget?.proteinTarget ?? profile.proteinTarget,
                carbsTarget: summaryForActiveDate?.carbsTarget ?? currentTarget?.carbsTarget ?? profile.carbsTarget,
                fatTarget: summaryForActiveDate?.fatTarget ?? currentTarget?.fatTarget ?? profile.fatTarget,
                hasData: !entries.isEmpty,
                dailyTargetId: summaryForActiveDate?.dailyTargetId ?? currentTarget?.id,
                dailyTargetName: summaryForActiveDate?.dailyTargetName ?? currentTarget?.name,
                createdAt: nil
            )
            try await summaryRepository.upsertSummary(summary)

            let nextDate = nextActiveDate(from: profile.activeDate)
            try await profileRepository.updateActiveDate(nextDate)
            try await profileRepository.updateActiveTarget(nextTarget.id)
            activeDate = nextDate
            self.entriesWithItems = []
            self.totals = .zero
            activeTarget = nextTarget
            targets = nextTarget.macroTargets
            availableTargets = try await targetRepository.fetchTargets()
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
            calories: Int(round(entries.reduce(0) { $0 + $1.calories })),
            protein: Int(round(entries.reduce(0) { $0 + $1.protein })),
            carbs: Int(round(entries.reduce(0) { $0 + $1.carbs })),
            fat: Int(round(entries.reduce(0) { $0 + $1.fat }))
        )
    }

    private func nextActiveDate(from dateString: String) -> String {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: dateFromString(dateString) ?? Date())
        let candidate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let today = calendar.startOfDay(for: Date())
        let nextDate = max(candidate, today)
        return Self.dateFormatter.string(from: nextDate)
    }

    private func dateFromString(_ value: String) -> Date? {
        Self.dateFormatter.date(from: value)
    }

    private func resolveActiveTarget(profile: Profile, targets: [DailyTarget]) -> DailyTarget? {
        if let activeTargetId = profile.activeTargetId,
           let matched = targets.first(where: { $0.id == activeTargetId }) {
            return matched
        }
        guard let fallback = targets.first else { return nil }
        Task {
            try? await profileRepository.updateActiveTarget(fallback.id)
        }
        return fallback
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
