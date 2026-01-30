import Foundation

@MainActor
final class SuggestionsViewModel: ObservableObject {
    @Published var mealType: SuggestionMealType = .meal
    @Published var maxPrepTimeMinutes: Int = 20
    @Published var ingredientNotes: String = ""

    @Published private(set) var remaining: MacroTotals = .zero
    @Published private(set) var targets: MacroTargets = .example
    @Published private(set) var totals: MacroTotals = .zero
    @Published private(set) var suggestions: [MealSuggestion] = []
    @Published private(set) var activeDate: String = ""
    @Published private(set) var isLoadingContext = false
    @Published private(set) var isLoadingSuggestions = false
    @Published var contextErrorMessage: String?
    @Published var suggestionErrorMessage: String?

    private let profileRepository: ProfileRepository
    private let entryRepository: FoodEntryRepository
    private let summaryRepository: DailySummaryRepository
    private let targetRepository: DailyTargetRepository
    private let suggestionService: AISuggestionService

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        entryRepository: FoodEntryRepository = FoodEntryRepository(),
        summaryRepository: DailySummaryRepository = DailySummaryRepository(),
        targetRepository: DailyTargetRepository = DailyTargetRepository(),
        suggestionService: AISuggestionService = AISuggestionService()
    ) {
        self.profileRepository = profileRepository
        self.entryRepository = entryRepository
        self.summaryRepository = summaryRepository
        self.targetRepository = targetRepository
        self.suggestionService = suggestionService
    }

    func loadContext() async {
        isLoadingContext = true
        contextErrorMessage = nil
        defer { isLoadingContext = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let defaultProfile = Profile.defaultTargets(
                for: userId,
                activeDate: Self.dateFormatter.string(from: Date())
            )
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            guard let profile = try await profileRepository.fetchProfile() else {
                contextErrorMessage = "Unable to load profile."
                return
            }

            let availableTargets = try await targetRepository.ensureTargets(for: profile)
            let resolvedTarget = resolveActiveTarget(profile: profile, targets: availableTargets)
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

            let entries = try await entryRepository.fetchEntries(
                for: dateFromString(activeDate) ?? Date(),
                timeZone: TimeZone.current
            )
            totals = Self.totals(from: entries)
            remaining = Self.remaining(targets: targets, totals: totals)
        } catch {
            contextErrorMessage = "Unable to load remaining macros."
        }
    }

    func fetchSuggestions(variationNote: String? = nil) async {
        if activeDate.isEmpty {
            await loadContext()
        }
        guard isValidPrepTime(maxPrepTimeMinutes) else {
            suggestionErrorMessage = "Prep time must be between 1 and 240 minutes."
            return
        }

        isLoadingSuggestions = true
        suggestionErrorMessage = nil
        defer { isLoadingSuggestions = false }

        do {
            let request = AISuggestionRequest(
                remaining: AISuggestionMacros(
                    calories: remaining.calories,
                    protein: remaining.protein,
                    carbs: remaining.carbs,
                    fat: remaining.fat
                ),
                mealType: mealType.rawValue,
                maxPrepMinutes: maxPrepTimeMinutes,
                count: 3,
                ingredientNotes: ingredientNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : ingredientNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                variationNote: variationNote,
                units: "grams"
            )

            let payloads = try await suggestionService.fetchSuggestions(request: request)
            suggestions = payloads.prefix(3).map { payload in
                let warning = Self.exceedWarning(for: payload, remaining: remaining)
                return MealSuggestion(
                    title: payload.title,
                    description: payload.description,
                    calories: Int(round(payload.calories)),
                    protein: Int(round(payload.protein)),
                    carbs: Int(round(payload.carbs)),
                    fat: Int(round(payload.fat)),
                    warning: warning,
                    notes: payload.notes
                )
            }
        } catch {
            suggestionErrorMessage = error.localizedDescription
        }
    }

    func regenerate(reason: SuggestionRegenerateReason) async {
        switch reason {
        case .ingredients(let notes):
            ingredientNotes = notes
            await fetchSuggestions(variationNote: "Adjust ingredients: \(notes)")
        case .time(let minutes):
            maxPrepTimeMinutes = clampPrepTime(minutes)
            await fetchSuggestions(variationNote: "Adjust prep time to \(maxPrepTimeMinutes) minutes")
        case .different:
            await fetchSuggestions(variationNote: "Different options")
        }
    }

    private func clampPrepTime(_ minutes: Int) -> Int {
        min(max(minutes, 1), 240)
    }

    private func isValidPrepTime(_ minutes: Int) -> Bool {
        minutes >= 1 && minutes <= 240
    }

    private static func totals(from entries: [FoodEntry]) -> MacroTotals {
        MacroTotals(
            calories: Int(round(entries.reduce(0) { $0 + $1.calories })),
            protein: Int(round(entries.reduce(0) { $0 + $1.protein })),
            carbs: Int(round(entries.reduce(0) { $0 + $1.carbs })),
            fat: Int(round(entries.reduce(0) { $0 + $1.fat }))
        )
    }

    private static func remaining(targets: MacroTargets, totals: MacroTotals) -> MacroTotals {
        MacroTotals(
            calories: targets.calories - totals.calories,
            protein: targets.protein - totals.protein,
            carbs: targets.carbs - totals.carbs,
            fat: targets.fat - totals.fat
        )
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

    private func dateFromString(_ value: String) -> Date? {
        Self.dateFormatter.date(from: value)
    }

    private static func exceedWarning(
        for payload: AISuggestionPayload,
        remaining: MacroTotals
    ) -> String? {
        let remainingCalories = Double(remaining.calories)
        let remainingProtein = Double(remaining.protein)
        let remainingCarbs = Double(remaining.carbs)
        let remainingFat = Double(remaining.fat)

        var parts: [String] = []

        if payload.calories > remainingCalories {
            let delta = Int(round(payload.calories - remainingCalories))
            parts.append("calories by \(delta) kcal")
        }
        if payload.protein > remainingProtein {
            let delta = Int(round(payload.protein - remainingProtein))
            parts.append("protein by \(delta) g")
        }
        if payload.carbs > remainingCarbs {
            let delta = Int(round(payload.carbs - remainingCarbs))
            parts.append("carbs by \(delta) g")
        }
        if payload.fat > remainingFat {
            let delta = Int(round(payload.fat - remainingFat))
            parts.append("fat by \(delta) g")
        }

        guard !parts.isEmpty else { return nil }
        return "Exceeds " + parts.joined(separator: ", ")
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

enum SuggestionRegenerateReason {
    case ingredients(String)
    case time(Int)
    case different
}
