import Foundation
import Supabase
import UIKit

struct StorageService {
    private let supabase: SupabaseClient
    private let bucket = "food-images"
    private let maxDimension: CGFloat = 1400
    private let jpegQuality: CGFloat = 0.75

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func uploadFoodImage(data: Data, userId: UUID, entryId: UUID) async throws -> String {
        let processedData = try processedImageData(from: data)
        let path = "\(userId.uuidString)/\(entryId.uuidString).jpg"
        let options = FileOptions(contentType: "image/jpeg", upsert: false)
        _ = try await supabase.storage.from(bucket).upload(path, data: processedData, options: options)
        return path
    }

    private func processedImageData(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw StorageError.processingFailed
        }

        let resizedImage = resize(image: image, maxDimension: maxDimension)
        guard let jpegData = resizedImage.jpegData(compressionQuality: jpegQuality) else {
            throw StorageError.processingFailed
        }

        return jpegData
    }

    private func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum StorageError: LocalizedError {
    case processingFailed

    var errorDescription: String? {
        "Unable to process the image."
    }
}
