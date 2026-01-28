import AVFoundation
import SwiftUI
import UIKit

/// A SwiftUI wrapper for UIImagePickerController configured for camera capture.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                // Compress to JPEG with reasonable quality for upload
                parent.imageData = image.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Utility to check camera availability and authorization status.
enum CameraAccess {
    case available
    case notAvailable
    case denied
    case restricted

    static func checkStatus() -> CameraAccess {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .notAvailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .available
        case .notDetermined:
            // Will prompt user when camera is presented
            return .available
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .notAvailable
        }
    }

    var errorMessage: String? {
        switch self {
        case .available:
            return nil
        case .notAvailable:
            return "Camera is not available on this device."
        case .denied:
            return "Camera access was denied. Please enable it in Settings."
        case .restricted:
            return "Camera access is restricted on this device."
        }
    }
}
