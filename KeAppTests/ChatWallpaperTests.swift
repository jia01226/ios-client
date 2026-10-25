import XCTest
import UIKit
import SwiftUI
@testable import KeApp

@MainActor
final class ChatWallpaperTests: XCTestCase {
    func testPhotoAndPreferencesSurviveReloadAndSolidDoesNotDeletePhoto() throws {
        let suite = "wallpaper-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ChatWallpaperStore(defaults: defaults, directory: directory)
        XCTAssertEqual(store.background, .atmosphere)
        XCTAssertEqual(store.blur, 0)
        XCTAssertEqual(store.dim, 0.1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        try store.save(source: image, cropped: image)
        store.blur = 12
        store.dim = 0.25
        let loaded = ChatWallpaperStore(defaults: defaults, directory: directory)
        XCTAssertEqual(loaded.background, .photo)
        XCTAssertNotNil(loaded.sourceImage)
        XCTAssertEqual(loaded.image?.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(loaded.image?.cgImage?.height, image.cgImage?.height)
        XCTAssertEqual(loaded.blur, 12)
        XCTAssertEqual(loaded.dim, 0.25)
        loaded.background = .atmosphere
        let solid = ChatWallpaperStore(defaults: defaults, directory: directory)
        XCTAssertEqual(solid.background, .atmosphere)
        XCTAssertNotNil(solid.image)
        // A replacement keeps only the current pair of files.
        try solid.save(source: image, cropped: image)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testCorruptOrMissingPhotoFallsBackWithoutTouchingGlassSetting() throws {
        let suite = "wallpaper-missing-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UUID().uuidString, forKey: "chat.wallpaper.photoID")
        defaults.set("photo", forKey: "chat.wallpaper.kind")
        defaults.set(true, forKey: "app.lockscreenGlass")
        defaults.set(99, forKey: "chat.wallpaper.blur")
        defaults.set(-1, forKey: "chat.wallpaper.dim")
        let store = ChatWallpaperStore(defaults: defaults, directory: .init(fileURLWithPath: "/nonexistent-wallpaper"))
        XCTAssertEqual(store.background, .atmosphere)
        XCTAssertNil(store.image)
        XCTAssertEqual(store.blur, 20)
        XCTAssertEqual(store.dim, 0)
        XCTAssertTrue(defaults.bool(forKey: "app.lockscreenGlass"))
        XCTAssertNil(ChatWallpaperStore.decode(Data("invalid image".utf8)))
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[3])
    }

    private func solid(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 137：模糊、压暗烤成一张：按原比例、中间照压暗变暗、边上照旧淡出（和实时模糊一样）；糊得重的缩小了烤
    func testBakedWallpaperMatchesLiveBlurAndDim() throws {
        let white = solid(100, 200)
        let screen = CGSize(width: 100, height: 200)
        let baked = try XCTUnwrap(ChatWallpaperStore.bake(white, blur: 4, dim: 0.25, shade: [0, 0, 0],
                                                          screen: screen, screenScale: 1)?.cgImage)
        XCTAssertEqual(baked.width, 100)
        XCTAssertEqual(baked.height, 200)
        let center = pixel(baked, x: 50, y: 100)
        XCTAssertEqual(Double(center.r), 255 * 0.75, accuracy: 3)
        XCTAssertEqual(center.a, 255)
        XCTAssertLessThan(pixel(baked, x: 0, y: 0).a, 255, "边上照旧淡出")
        XCTAssertNil(ChatWallpaperStore.bake(white, blur: 0, dim: 0.25, shade: [0, 0, 0], screen: screen, screenScale: 1))
        let heavy = try XCTUnwrap(ChatWallpaperStore.bake(white, blur: 20, dim: 0, shade: [0, 0, 0],
                                                          screen: CGSize(width: 50, height: 100), screenScale: 3)?.cgImage)
        XCTAssertEqual(heavy.width, 50)
        XCTAssertEqual(heavy.height, 100)
    }

    /// 137：换照片、拖滑杆：没烤好之前照旧实时模糊，手停一下就换成烤好的那张
    func testBakedWallpaperFollowsPhotoAndSliders() async throws {
        let suite = "wallpaper-bake-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ChatWallpaperStore(defaults: defaults, directory: directory)
        try store.save(source: solid(60, 120), cropped: solid(60, 120))
        XCTAssertNil(store.bakedImage, "不模糊就不烤")
        func settled() async {
            for _ in 0..<100 where store.bakedImage == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        }
        store.blur = 8
        XCTAssertNil(store.bakedImage, "拖的时候照旧实时模糊")
        await settled()
        XCTAssertNotNil(store.bakedImage)
        store.dim = 0.3
        XCTAssertNil(store.bakedImage, "压暗换了，旧的那张不用")
        await settled()
        XCTAssertNotNil(store.bakedImage)
        XCTAssertEqual(store.baked?.dim, 0.3)
        try store.save(source: solid(80, 160), cropped: solid(80, 160))
        XCTAssertNil(store.bakedImage, "换了照片，旧的那张不用")
        await settled()
        XCTAssertTrue(store.baked?.source === store.image)
    }

    func testCropTracksPanAndZoomAndMaintainsViewportAspect() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        }
        let scroll = WallpaperCropScrollView(image: image, zoomLimit: 6)
        scroll.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scroll.layoutIfNeeded()
        let center = try XCTUnwrap(scroll.croppedImage())
        scroll.contentOffset = CGPoint(x: 200, y: 0)
        let right = try XCTUnwrap(scroll.croppedImage())
        XCTAssertNotEqual(center.pngData(), right.pngData())
        XCTAssertEqual(right.size.width / right.size.height, 1, accuracy: 0.001)
        scroll.zoomScale = scroll.minimumZoomScale * 2
        scroll.contentOffset = CGPoint(x: 0, y: 0)
        let zoomed = try XCTUnwrap(scroll.croppedImage())
        XCTAssertNotEqual(right.pngData(), zoomed.pngData())
        XCTAssertEqual(zoomed.size, right.size)
    }
    // Component screenshots run in the existing unit-test job; full interaction
    // coverage remains in ChatWallpaperInteractionTests for an Xcode UI-test run.
    func testLockscreenComponentsRenderInDayNightAndLargeType() async throws {
        let theme = Theme.shared
        let previousGlass = theme.lockscreenGlass
        let previousSkin = theme.skin
        defer { theme.lockscreenGlass = previousGlass; theme.skin = previousSkin }
        let oldWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.windowScene = oldWindow?.windowScene
        defer { window.isHidden = true; oldWindow?.makeKeyAndVisible() }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 780)).image { context in
            UIColor.systemYellow.setFill(); context.fill(CGRect(x: 0, y: 0, width: 360, height: 390))
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 390, width: 360, height: 390))
        }
        theme.lockscreenGlass = true
        for skin in [Skin.day, .night] {
            theme.skin = skin
            let root = ZStack {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
                Color.black.opacity(0.1).ignoresSafeArea()
                VStack(spacing: theme.metric.gapL) {
                    MessageRow(message: Message(id: "preview-ke", sender: .ke, text: "照片透过玻璃，文字保持清楚。", time: .now),
                               isHighlighted: false, visibleSegmentCount: nil, onAttachmentTap: { _ in })
                    ThinkingTimelineRow(onOpen: {})
                    MessageRow(message: Message(id: "preview-me", sender: .me, text: "两边用同一种透明玻璃。", time: .now),
                               isHighlighted: false, visibleSegmentCount: nil, onAttachmentTap: { _ in })
                    Spacer()
                    TextField("和柯说点什么…", text: .constant("白色输入文字"))
                        .foregroundStyle(theme.chatTextPrimary).modifier(ChatLegibility())
                        .padding(theme.metric.gapL)
                        .background(FloatingGlassSurface(cornerRadius: theme.metric.radiusComposer, lockscreen: true))
                }.padding(theme.metric.pagePadding)
            }
            .environmentObject(theme)
            .environment(\.colorScheme, skin == .night ? .dark : .light)
            .environment(\.dynamicTypeSize, skin == .night ? .accessibility3 : .large)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 500_000_000)
            let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertGreaterThan(rendered.size.width, 0)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "lockscreen-components-\(skin.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

}
