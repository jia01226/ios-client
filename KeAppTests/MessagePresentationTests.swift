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

    func testUploadResponseAcceptsBackendContractWithoutKind() throws {
        let data = Data(#"{"url":"/uploads/example.jpg","name":"照片.jpg"}"#.utf8)
        let response = try JSONDecoder().decode(UploadResponse.self, from: data)

        XCTAssertEqual(response.attachment.url, "/uploads/example.jpg")
        XCTAssertTrue(response.attachment.isImage)
    }

    func testAssistantThinkingBecomesASeparateTimelineItem() {
        let message = Message(
            id: "assistant-with-thinking",
            sender: .ke,
            text: "正文",
            time: .now,
            thoughtSummary: "真思考",
            thoughtNote: "小念头"
        )

        let items = ChatTimelineItem.make(
            message: message,
            isHighlighted: false,
            visibleSegmentCount: nil
        )

        XCTAssertEqual(items.map(\.kind), [.thinking, .message])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(items.map(\.messageID), [message.id, message.id])
    }

    func testBlankOrUserThinkingDoesNotCreateAnEntry() {
        let blankAssistant = Message(
            id: "assistant-with-blank-thinking",
            sender: .ke,
            text: "正文",
            time: .now,
            thoughtSummary: "  \n "
        )
        let user = Message(
            id: "user-with-thinking",
            sender: .me,
            text: "正文",
            time: .now,
            thoughtSummary: "不应展示"
        )

        for message in [blankAssistant, user] {
            let items = ChatTimelineItem.make(
                message: message,
                isHighlighted: false,
                visibleSegmentCount: nil
            )
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.kind, .message)
        }
    }
}
