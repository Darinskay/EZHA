import Foundation
import Supabase

struct StorageService {
    private let supabase: SupabaseClient
    private let bucket = "food-images"

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func uploadFoodImage(data: Data, userId: UUID, entryId: UUID) async throws -> String {
        let path = "\(userId.uuidString)/\(entryId.uuidString).jpg"
        let options = FileOptions(contentType: "image/jpeg", upsert: false)
        _ = try await supabase.storage.from(bucket).upload(path, data: data, options: options)
        return path
    }
}
