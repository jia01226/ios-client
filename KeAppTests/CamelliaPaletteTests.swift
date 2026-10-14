import XCTest
@testable import KeApp

final class CamelliaPaletteTests: XCTestCase {
    func testExactlyFourPalettesWithoutOriginalBlue() {
        XCTAssertEqual(CamelliaPalette.allCases.map(\.rawValue), ["mist", "white", "ivory", "cream"])
        XCTAssertEqual(CamelliaPalette.allCases.map(\.label), ["浅雾蓝", "冷白", "暖白", "浅米色"])
    }

    func testMissingAndUnknownValuesFallBackToIvory() {
        for value in ["", "blue", "deleted-palette"] {
            XCTAssertEqual(CamelliaPalette.resolve(value), .ivory)
        }
    }

    func testPalettesRoundTripThroughLocalPreferences() throws {
        let suite = "CamelliaPaletteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for palette in CamelliaPalette.allCases {
            defaults.set(palette.rawValue, forKey: CamelliaPalette.storageKey)
            XCTAssertEqual(CamelliaPalette.resolve(defaults.string(forKey: CamelliaPalette.storageKey) ?? ""), palette)
        }
    }

    func testColorComponentsAndMistStayInRange() {
        for palette in CamelliaPalette.allCases {
            let (r, g, b) = palette.paperRGB
            XCTAssertTrue([r, g, b].allSatisfy { (0.85...1).contains($0) })
            XCTAssertTrue((0...1).contains(palette.mistOpacity))
            XCTAssertTrue((0...1).contains(palette.mistSaturation))
        }
        XCTAssertEqual(CamelliaPalette.cream.paperRGB.0, 244.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(CamelliaPalette.white.mistSaturation, 0)
    }
}
