import SwiftUI
import UIKit
import ImageIO

/// 照片只写本机 Application Support，不进入聊天附件或网络请求。
@MainActor
final class ChatWallpaperStore: ObservableObject {
    static let shared = ChatWallpaperStore()
    enum Background: String { case atmosphere, photo }

    @Published private(set) var image: UIImage?
    @Published private(set) var sourceImage: UIImage?
    @Published var background: Background {
        didSet { defaults.set(background.rawValue, forKey: "chat.wallpaper.kind") }
    }
    @Published var blur: Double {
        didSet { defaults.set(blur, forKey: "chat.wallpaper.blur") }
    }
    @Published var dim: Double {
        didSet { defaults.set(dim, forKey: "chat.wallpaper.dim") }
    }
    private let defaults: UserDefaults
    private let directory: URL

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatWallpaper", isDirectory: true)
        blur = min(max(defaults.double(forKey: "chat.wallpaper.blur"), 0), 20)
        dim = min(max(defaults.object(forKey: "chat.wallpaper.dim") as? Double ?? 0.1, 0), 0.4)
        // A manifest switches both files together; incomplete writes never replace the old wallpaper.
        if let name = defaults.string(forKey: "chat.wallpaper.photoID"), UUID(uuidString: name) != nil {
            image = UIImage(contentsOfFile: self.directory.appendingPathComponent(name + "-crop.jpg").path)
            sourceImage = UIImage(contentsOfFile: self.directory.appendingPathComponent(name + "-source.jpg").path)
        }
        background = image == nil ? .atmosphere
            : Background(rawValue: defaults.string(forKey: "chat.wallpaper.kind") ?? "") ?? .atmosphere
    }

    func save(source: UIImage, cropped: UIImage) throws {
        guard let sourceData = source.jpegData(compressionQuality: 0.9),
              let cropData = cropped.jpegData(compressionQuality: 0.92) else { throw WallpaperError.invalidImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let sourceURL = directory.appendingPathComponent(name + "-source.jpg")
        let cropURL = directory.appendingPathComponent(name + "-crop.jpg")
        do {
            try sourceData.write(to: sourceURL, options: .atomic)
            try cropData.write(to: cropURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: cropURL)
            throw error
        }
        let oldName = defaults.string(forKey: "chat.wallpaper.photoID")
        defaults.set(name, forKey: "chat.wallpaper.photoID")
        sourceImage = source
        image = cropped
        background = .photo
        if let oldName, UUID(uuidString: oldName) != nil {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldName + "-source.jpg"))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldName + "-crop.jpg"))
        }
    }

    nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    enum WallpaperError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "这张照片没能读取或保存，请重新选一张。" }
    }
}

struct ChatWallpaperBackground: View {
    @ObservedObject var store: ChatWallpaperStore
    @EnvironmentObject private var theme: Theme
    var body: some View {
        GeometryReader { geometry in
            if store.background == .photo, let image = store.image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: store.blur)
                    .overlay(theme.wallpaper.shade.opacity(store.dim))
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
