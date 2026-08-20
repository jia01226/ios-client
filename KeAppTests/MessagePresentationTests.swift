import XCTest
@testable import KeApp

final class MessagePresentationTests: XCTestCase {
    func testDailyReplyKeepsSeparateBubbles() {
        let message = Message(
            id: "daily",
            sender: .ke,
            text: "先过来。\n\n让我抱一下。\n\n再慢慢说。",
            time: .now
        )

        XCTAssertEqual(
            message.bubbleSegments,
            ["先过来。", "让我抱一下。", "再慢慢说。"]
        )
    }

    func testLongReplyStaysInOneBubble() {
        let first = String(repeating: "这件事我会陪你慢慢讲清楚。", count: 8)
        let second = String(repeating: "你不用急着把自己推到结论那里。", count: 8)
        let message = Message(
            id: "deep-talk",
            sender: .ke,
            text: "\(first)\n\n\(second)",
            time: .now
        )

        XCTAssertEqual(message.bubbleSegments.count, 1)
        XCTAssertTrue(message.bubbleSegments[0].contains("\n\n"))
    }

    func testBedroomReplyAlwaysStaysInOneBubble() {
        let message = Message(
            id: "bedroom",
            sender: .ke,
            text: "第一段。\n\n第二段。\n\n第三段。",
            time: .now,
            sceneMode: "bedroom"
        )

        XCTAssertEqual(message.bubbleSegments.count, 1)
    }

    func testHistoricalImageWithoutKindStillOpensAsImage() {
        let attachment = ChatAttachment(
            url: "/uploads/example.jpg",
            name: "照片.jpg",
            kind: ""
        )

        XCTAssertTrue(attachment.isImage)
    }
}
