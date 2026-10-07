import XCTest
import UIKit
@testable import KeApp

@MainActor
final class QuoteNotebookTests: XCTestCase {
    func testJournalFontIsBundled() {
        XCTAssertNotNil(UIFont(name: "NotoSerifSC-ExtraLight", size: 16), "Journal must not silently fall back to sans serif")
    }

    func testDifferentBubbleSegmentsPersistWithSpeakerDateAndMood() {
        let suite = "notebook-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let notebook = QuoteNotebook(defaults: defaults)
        let message = Message(id: "reply", sender: .ke, text: "第一句\n\n第二句", time: Date(timeIntervalSince1970: 100))
        notebook.collect(message, text: "第一句")
        notebook.collect(message, text: "第一句")
        notebook.collect(message, text: "第二句")
        XCTAssertEqual(notebook.pages.count, 2)
        XCTAssertEqual(notebook.pages[0].speaker, "柯")
        XCTAssertEqual(notebook.pages[0].spokenAt, message.time)
        notebook.writeMood("想记住这句话", for: notebook.pages[0].id)
        let restored = QuoteNotebook(defaults: defaults)
        XCTAssertEqual(restored.pages[0].mood, "想记住这句话")
        XCTAssertEqual(restored.pages[1].text, "第一句")
        let own = Message(id: "own", sender: .me, text: "我的话", time: message.time)
        notebook.collect(own)
        XCTAssertEqual(notebook.pages[0].speaker, "佳佳")
    }
}
