import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var caloriesText = ""
    @Published var proteinText = ""
    @Published var carbsText = ""
    @Published var fatText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var saveMessage: String?

    private let profileRepository: ProfileRepository

    init(profileRepository: ProfileRepository = ProfileRepository()) {
        self.profileRepository = profileRepository
    }

    func loadTargets() async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        defer { isLoading = false }

        do {
            let userId = try await SupabaseConfig.client.auth.session.user.id
            let defaultProfile = Profile.defaultTargets(for: userId)
            try await profileRepository.ensureProfileRowExists(defaultTargets: defaultProfile)

            if let profile = try await profileRepository.fetchProfile() {
                caloriesText = String(Int(profile.caloriesTarget))
                proteinText = String(Int(profile.proteinTarget))
                carbsText = String(Int(profile.carbsTarget))
                fatText = String(Int(profile.fatTarget))
            }
        } catch {
            errorMessage = "Unable to load targets."
        }
    }

    func saveTargets() async {
        isLoading = true
        errorMessage = nil
        saveMessage = nil
        defer { isLoading = false }

        guard let calories = Double(caloriesText),
              let protein = Double(proteinText),
              let carbs = Double(carbsText),
              let fat = Double(fatText) else {
            errorMessage = "Enter valid numbers for targets."
            return
        }

        do {
            try await profileRepository.upsertProfileTargets(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            )
            saveMessage = "Targets saved."
        } catch {
            errorMessage = "Unable to save targets."
        }
    }
}
