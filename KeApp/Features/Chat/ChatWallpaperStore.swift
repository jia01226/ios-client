import SwiftUI
import UIKit
import ImageIO
import CoreImage

/// 照片只写本机 Application Support，不进入聊天附件或网络请求。
@MainActor
final class ChatWallpaperStore: ObservableObject {
    static let shared = ChatWallpaperStore()
    enum Background: String { case atmosphere, photo }

    @Published private(set) var image: UIImage?
    @Published private(set) var sourceImage: UIImage?
    @Published var background: Background {
        didSet {
            defaults.set(background.rawValue, forKey: "chat.wallpaper.kind")
            scheduleBake(after: 0)
        }
    }
    @Published var blur: Double {
        didSet {
            defaults.set(blur, forKey: "chat.wallpaper.blur")
            scheduleBake(after: Self.bakeDelay)
        }
    }
    @Published var dim: Double {
        didSet {
            defaults.set(dim, forKey: "chat.wallpaper.dim")
            scheduleBake(after: Self.bakeDelay)
        }
    }
    /// 137：模糊、压暗烤好的那张（连同烤它时的照片和两档数值）。背景直接显示它，
    /// 不再整屏实时模糊——滑聊天时那一层每帧都要重新算。
    @Published private(set) var baked: Baked?
    struct Baked {
        let image: UIImage
        let source: UIImage
        let blur: Double
        let dim: Double
    }
    private var bakeTask: Task<Void, Never>?
    /// 拖滑杆时等手停一下再烤，拖的过程照旧实时模糊
    static let bakeDelay: Double = 0.25
    private let defaults: UserDefaults
    private let directory: URL

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatWallpaper", isDirectory: true)
        blur = min(max(defaults.double(forKey: "chat.wallpaper.blur"), 0), 20)
        dim = min(max(defaults.object(forKey: "chat.wallpaper.dim") as? Double ?? 0.1, 0), 0.4)
        background = .atmosphere
        // A manifest switches both files together; incomplete writes never replace the old wallpaper.
        if let name = defaults.string(forKey: "chat.wallpaper.photoID"), UUID(uuidString: name) != nil {
            image = UIImage(contentsOfFile: self.directory.appendingPathComponent(name + "-crop.jpg").path)
            sourceImage = UIImage(contentsOfFile: self.directory.appendingPathComponent(name + "-source.jpg").path)
        }
        background = image == nil ? .atmosphere
            : Background(rawValue: defaults.string(forKey: "chat.wallpaper.kind") ?? "") ?? .atmosphere
        scheduleBake(after: 0)
    }

    /// 137：现在这张照片、这档模糊和压暗烤好的那张；还没烤好（刚换照片、正在拖滑杆）是 nil
    var bakedImage: UIImage? {
        guard let baked, let image, baked.source === image, baked.blur == blur, baked.dim == dim else { return nil }
        return baked.image
    }

    private func scheduleBake(after delay: Double) {
        bakeTask?.cancel()
        bakeTask = nil
        // 不模糊就用不着烤：照片原样、压暗那一层本来就不费事
        guard background == .photo, let image, blur > 0 else { return }
        let blur = blur, dim = dim
        let screen = UIScreen.main.bounds.size
        let screenScale = UIScreen.main.scale
        // 压暗用的颜色照 Theme 里的 wallpaper.shade
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Theme.shared.wallpaper.shade).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let shade = [Double(red), Double(green), Double(blue)]
        bakeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            let output = await Task.detached(priority: .utility) {
                ChatWallpaperStore.bake(image, blur: blur, dim: dim, shade: shade, screen: screen, screenScale: screenScale)
            }.value
            guard !Task.isCancelled, let self, let output, self.image === image else { return }
            self.baked = Baked(image: output, source: image, blur: blur, dim: dim)
        }
    }

    /// 137：把模糊和压暗烤进一张图，铺在屏幕上和以前实时模糊、再压一层黑的样子一样：
    /// 模糊半径按屏幕上的点换算成这张图的像素；边上照旧淡出（外面当透明），压暗照「盖在上面」的算法叠。
    /// 模糊过的图用不着满分辨率：越糊缩得越小再糊（省内存、也快），铺上去看不出来。
    nonisolated static func bake(_ image: UIImage, blur: Double, dim: Double, shade: [Double],
                                 screen: CGSize, screenScale: CGFloat) -> UIImage? {
        let size = image.size
        guard blur > 0, size.width > 0, size.height > 0, screen.width > 0, screen.height > 0 else { return nil }
        // 照片按 scaledToFill 铺满屏幕：一个照片点占几个屏幕点
        let fill = max(screen.width / size.width, screen.height / size.height)
        // 烤出来的图每个屏幕点几个像素：模糊越重越用不着细；不比原图更细
        let perScreenPoint = min(screenScale, max(1, 6 / blur))
        let perImagePoint = min(image.scale, fill * perScreenPoint)
        let target = CGSize(width: max(1, (size.width * perImagePoint).rounded()),
                            height: max(1, (size.height * perImagePoint).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let small = UIGraphicsImageRenderer(size: target, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let cgImage = small.cgImage, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let rect = input.extent
        let pixelsPerScreenPoint = Double(perImagePoint / fill)
        var output = input.applyingGaussianBlur(sigma: blur * pixelsPerScreenPoint).cropped(to: rect)
        if dim > 0, shade.count == 3 {
            output = CIImage(color: CIColor(red: shade[0], green: shade[1], blue: shade[2], alpha: CGFloat(dim)))
                .cropped(to: rect)
                .composited(over: output)
        }
        // 不换到线性色彩里算：和屏幕上实时模糊、叠一层黑是同一种算法，颜色深浅一样
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        guard let result = context.createCGImage(output, from: rect, format: .RGBA8, colorSpace: sRGB) else { return nil }
        return UIImage(cgImage: result)
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
        background = .photo   // 137：它的 didSet 会照新照片重烤
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
                if let baked = store.bakedImage {
                    // 137：模糊、压暗都烤在这张里了，滑聊天时不用每帧再算
                    Image(uiImage: baked)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    // 还没烤好（刚换照片、正在拖滑杆）：照旧实时模糊
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: store.blur)
                        .overlay(theme.wallpaper.shade.opacity(store.dim))
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
