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
