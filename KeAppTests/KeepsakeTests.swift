import XCTest
import UIKit
@testable import KeApp

@MainActor
final class KeepsakeTests: XCTestCase {
    func testOnlyOneKeWindowUsesExistingRoutedEndpointAndCache() {
        XCTAssertEqual(ChatLine.allCases, [.test1])
        XCTAssertEqual(ChatLine.allCases[0].title, "柯")
        XCTAssertEqual(ChatLine.allCases[0].apiBaseURL.path, "/ke-test1")
        XCTAssertEqual(ChatLine.allCases[0].cacheFileName, "messages-test1.json")
    }
    func testEveryProductionCutoutIsBundledWithAlpha() throws {
        for name in ["MoonTarotBack"] {
            let image = try XCTUnwrap(UIImage(named: name), name)
            let cg = try XCTUnwrap(image.cgImage, name)
            XCTAssertGreaterThan(cg.width, 200, name)
            XCTAssertTrue([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(cg.alphaInfo), name)
        }
    }
}
