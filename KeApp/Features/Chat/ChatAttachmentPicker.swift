import SwiftUI
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

private enum ChatAttachmentEncodingPolicy {
    static let maximumImageDimension: CGFloat = 2560
    static let jpegQuality: CGFloat = 0.84
}

extension UIImage {
    /// 相机原图常有四五千万像素；聊天上传保留清晰度即可，先收至合理边长，
    /// 避免大图长时间占着上传状态，看起来像一直在转。
    func chatUploadJPEGData() -> Data? {
        let longest = max(size.width, size.height)
        guard longest > ChatAttachmentEncodingPolicy.maximumImageDimension else {
            return jpegData(compressionQuality: ChatAttachmentEncodingPolicy.jpegQuality)
        }
        let scale = ChatAttachmentEncodingPolicy.maximumImageDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: ChatAttachmentEncodingPolicy.jpegQuality)
    }
}

/// 137：聊天里发照片。解码、缩边、压 JPEG 都在后台做——以前在主线程，点一张最近的照片、
/// 从相册选几张、拍完照，界面都会冻住零点几秒到一两秒。
/// 她说「不是压缩图片」：清晰度不降，最长边 2048、JPEG 质量 0.85。
enum ChatPhotoEncoder {
    static let maxPixelSize = 2048
    static let quality: CGFloat = 0.85

    /// 相册、最近照片给的原图数据 → 发出去的 JPEG；读不出来是 nil
    static func jpeg(from data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { encode(data) }.value
    }

    /// 拍完照拿到的那张
    static func jpeg(from image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { encode(image) }.value
    }

    /// 按目标尺寸直接解码（不先把四五千万像素的整张解出来），照片的方向一并摆正
    static func encode(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func encode(_ image: UIImage) -> Data? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longest = max(width, height)
        guard longest > 0 else { return nil }
        let limit = CGFloat(maxPixelSize)
        guard longest > limit else { return image.jpegData(compressionQuality: quality) }
        let ratio = limit / longest
        let target = CGSize(width: (width * ratio).rounded(), height: (height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

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
                let type = uti.flatMap { UTType($0) } ?? .jpeg
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
