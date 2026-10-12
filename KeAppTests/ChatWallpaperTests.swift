import XCTest
import UIKit
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
        XCTAssertEqual(loaded.image?.size, image.size)
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
}
