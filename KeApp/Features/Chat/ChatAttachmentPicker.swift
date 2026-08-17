import SwiftUI
import Photos
import UIKit
import UniformTypeIdentifiers

struct RecentPhoto: Identifiable {
    let id: String
    let thumbnail: UIImage
}

@MainActor
final class RecentPhotosStore: ObservableObject {
    @Published private(set) var photos: [RecentPhoto] = []
    @Published private(set) var permissionDenied = false
    @Published private(set) var isLoading = false

    private let imageManager = PHCachingImageManager()
    private var didLoad = false

    func loadIfNeeded() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let authorizationBecameAvailable = permissionDenied
            && (current == .authorized || current == .limited)
        guard !didLoad || authorizationBecameAvailable else { return }
        didLoad = true
        isLoading = true
        permissionDenied = false
        defer { isLoading = false }

        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) {
                    continuation.resume(returning: $0)
                }
            }
        } else {
            status = current
        }

        guard status == .authorized || status == .limited else {
            permissionDenied = true
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 24
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var loaded: [RecentPhoto] = []
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            if let image = await thumbnail(for: asset) {
                loaded.append(RecentPhoto(id: asset.localIdentifier, thumbnail: image))
            }
        }
        photos = loaded
    }

    func imageData(for identifier: String) async -> (data: Data, fileName: String, mimeType: String)? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            var completed = false
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard !completed else { return }
                completed = true
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                let type = uti.map { UTType($0) } ?? .jpeg
                let ext = type.preferredFilenameExtension ?? "jpg"
                continuation.resume(returning: (
                    data,
                    "照片-\(UUID().uuidString.prefix(8)).\(ext)",
                    type.preferredMIMEType ?? "image/jpeg"
                ))
            }
        }
    }

    private func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            var completed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 180, height: 180),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                guard !degraded, !completed else { return }
                completed = true
                continuation.resume(returning: image)
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
