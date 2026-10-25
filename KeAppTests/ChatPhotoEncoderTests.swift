import XCTest
import UIKit
import ImageIO
@testable import KeApp

/// 137：聊天发的照片在后台缩好：最长边 2048、按原比例、方向摆正；小图不放大
@MainActor
final class ChatPhotoEncoderTests: XCTestCase {
    private func pixelSize(_ jpeg: Data?) -> CGSize? {
        guard let jpeg, let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    private func photo(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
    }

    func testLargePhotoDataShrinksToLongEdge2048KeepingAspect() async throws {
        let original = try XCTUnwrap(photo(4000, 3000).pngData())
        let jpeg = await ChatPhotoEncoder.jpeg(from: original)
        let size = try XCTUnwrap(pixelSize(jpeg))
        XCTAssertEqual(max(size.width, size.height), 2048)
        XCTAssertEqual(size.width / size.height, 4.0 / 3.0, accuracy: 0.01)
    }

    func testSmallPhotoIsNotEnlarged() async throws {
        let original = try XCTUnwrap(photo(800, 600).pngData())
        let jpeg = await ChatPhotoEncoder.jpeg(from: original)
        let size = try XCTUnwrap(pixelSize(jpeg))
        XCTAssertEqual(size, CGSize(width: 800, height: 600))
        let broken = await ChatPhotoEncoder.jpeg(from: Data("不是图片".utf8))
        XCTAssertNil(broken)
    }

    func testCameraPhotoShrinksAndKeepsOrientation() async throws {
        let upright = photo(3000, 4000)
        let jpeg = await ChatPhotoEncoder.jpeg(from: upright)
        let size = try XCTUnwrap(pixelSize(jpeg))
        XCTAssertEqual(size, CGSize(width: 1536, height: 2048))
        // 相机常给横着存、带「向右转」方向的图：发出去的是摆正的竖图
        let sideways = UIImage(cgImage: try XCTUnwrap(photo(4000, 3000).cgImage), scale: 1, orientation: .right)
        let turnedJPEG = await ChatPhotoEncoder.jpeg(from: sideways)
        let turned = try XCTUnwrap(pixelSize(turnedJPEG))
        XCTAssertEqual(turned, CGSize(width: 1536, height: 2048))
    }
}
