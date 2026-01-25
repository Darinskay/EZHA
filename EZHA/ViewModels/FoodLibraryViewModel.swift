import Foundation

@MainActor
final class FoodLibraryViewModel: ObservableObject {
    @Published private(set) var foods: [SavedFood] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let repository: SavedFoodRepository

    init(repository: SavedFoodRepository = SavedFoodRepository()) {
        self.repository = repository
    }

    func loadFoods() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            foods = try await repository.fetchFoods()
        } catch {
            errorMessage = "Unable to load saved foods: \(error.localizedDescription)"
        }
    }

    func saveFood(id: UUID? = nil, draft: SavedFoodDraft) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let id {
                try await repository.updateFood(id: id, draft: draft)
            } else {
                try await repository.insertFood(draft)
            }
            foods = try await repository.fetchFoods()
            return true
        } catch {
            errorMessage = "Unable to save food: \(error.localizedDescription)"
            return false
        }
    }

    func deleteFood(id: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await repository.deleteFood(id: id)
            foods = try await repository.fetchFoods()
        } catch {
            errorMessage = "Unable to delete food: \(error.localizedDescription)"
        }
    }
}
