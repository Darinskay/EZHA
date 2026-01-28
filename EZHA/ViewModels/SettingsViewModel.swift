import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var targets: [DailyTarget] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var saveMessage: String?

    private let profileRepository: ProfileRepository
    private let targetRepository: DailyTargetRepository

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        targetRepository: DailyTargetRepository = DailyTargetRepository()
    ) {
        self.profileRepository = profileRepository
        self.targetRepository = targetRepository
    }

    func loadTargets() async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        defer { isLoading = false }

        do {
            let userId = try await SupabaseConfig.currentUserId()
            let defaultProfile = Profile.defaultTargets(
                for: userId,
                activeDate: Self.dateFormatter.string(from: Date())
            )
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            if let profile = try await profileRepository.fetchProfile() {
                targets = try await targetRepository.ensureTargets(for: profile)
                if profile.activeTargetId == nil, let firstTarget = targets.first {
                    try await profileRepository.updateActiveTarget(firstTarget.id)
                }
            }
        } catch {
            errorMessage = "Unable to load targets."
        }
    }

    func saveTarget(_ input: DailyTargetInput) async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        defer { isLoading = false }

        do {
            if let id = input.id {
                try await targetRepository.updateTarget(
                    id: id,
                    name: input.name,
                    calories: input.calories,
                    protein: input.protein,
                    carbs: input.carbs,
                    fat: input.fat
                )
            } else {
                try await targetRepository.insertTarget(
                    name: input.name,
                    calories: input.calories,
                    protein: input.protein,
                    carbs: input.carbs,
                    fat: input.fat
                )
            }
            if let profile = try await profileRepository.fetchProfile(), profile.activeTargetId == nil {
                let updatedTargets = try await targetRepository.fetchTargets()
                if let firstTarget = updatedTargets.first {
                    try await profileRepository.updateActiveTarget(firstTarget.id)
                }
            }
            targets = try await targetRepository.fetchTargets()
            saveMessage = "Target saved."
        } catch {
            errorMessage = "Unable to save targets."
        }
    }

    func deleteTarget(id: UUID) async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        defer { isLoading = false }

        do {
            try await targetRepository.deleteTarget(id: id)
            targets = try await targetRepository.fetchTargets()
            if let profile = try await profileRepository.fetchProfile(),
               profile.activeTargetId == id,
               let replacement = targets.first {
                try await profileRepository.updateActiveTarget(replacement.id)
            }
        } catch {
            errorMessage = "Unable to delete target."
        }
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
