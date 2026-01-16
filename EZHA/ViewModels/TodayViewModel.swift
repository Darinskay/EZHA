import Foundation
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var targets: MacroTargets = .example
    @Published private(set) var totals: MacroTotals = .zero
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let profileRepository: ProfileRepository
    private let entryRepository: FoodEntryRepository

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository()
    ) {
        self.profileRepository = profileRepository
        self.entryRepository = entryRepository
    }

    func loadToday() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let userId = try await SupabaseConfig.client.auth.session.user.id
            let defaultProfile = Profile.defaultTargets(for: userId)
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            if let profile = try await profileRepository.fetchProfile() {
                targets = MacroTargets(
                    calories: Int(profile.caloriesTarget),
                    protein: Int(profile.proteinTarget),
                    carbs: Int(profile.carbsTarget),
                    fat: Int(profile.fatTarget)
                )
            }

            let entries = try await entryRepository.fetchEntries(
                for: Date(),
                timeZone: TimeZone.current
            )
            totals = Self.totals(from: entries)
        } catch {
            errorMessage = "Unable to load today's data."
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
}
