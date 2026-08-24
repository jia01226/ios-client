import XCTest
@testable import KeApp


final class ChatStreamContractTests: XCTestCase {
    func testNoticeDoesNotReplaceFollowingTextEvent() throws {
        let payload = #"{"notice":"主线路一直忙，爸爸走小路过来了——说话可能慢一点。","t":"正文还在继续。"}"#

        let events = try APIClient.parseStreamPayload(payload)

        XCTAssertEqual(events, [
            .notice("主线路一直忙，爸爸走小路过来了——说话可能慢一点。"),
            .text("正文还在继续。"),
        ])
    }

    func testSplitCreatesThreeLocalMessagesAndMapsThreeServerIDs() {
        var assembly = ChatReplyStreamAssembly(rootMessageID: "assistant-local")

        XCTAssertEqual(assembly.messageIDForIncomingText().id, "assistant-local")
        assembly.receiveSplit()
        XCTAssertEqual(assembly.messageIDForIncomingText().id, "assistant-local-part-2")
        assembly.receiveSplit()
        XCTAssertEqual(assembly.messageIDForIncomingText().id, "assistant-local-part-3")

        XCTAssertEqual(assembly.localMessageIDs, [
            "assistant-local",
            "assistant-local-part-2",
            "assistant-local-part-3",
        ])
        let assignments = assembly.serverIDAssignments(
            assistantMessageIDs: [4209, 4210, 4211],
            legacyAssistantMessageID: 4211
        )
        XCTAssertEqual(assignments.map { $0.localMessageID }, assembly.localMessageIDs)
        XCTAssertEqual(assignments.map { $0.serverMessageID }, [4209, 4210, 4211])
    }

    func testTextIsDeliveredBeforeSplitBoundaryFromSamePayload() throws {
        let events = try APIClient.parseStreamPayload(#"{"t":"这一条说完。","split":true}"#)

        XCTAssertEqual(events, [.text("这一条说完。"), .split])
    }

    func testDoneParsesOrderedAssistantMessageIDs() throws {
        let payload = #"{"done":true,"assistant_message_id":4211,"assistant_message_ids":[4209,"4210",4211]}"#

        let events = try APIClient.parseStreamPayload(payload)

        XCTAssertEqual(events, [
            .completed(
                assistantMessageID: 4211,
                assistantMessageIDs: [4209, 4210, 4211],
                bedroom: nil
            )
        ])
    }

    func testNoSplitKeepsLongReplyInOneLocalMessage() {
        var assembly = ChatReplyStreamAssembly(rootMessageID: "assistant-long")
        let first = assembly.messageIDForIncomingText()
        let second = assembly.messageIDForIncomingText()

        XCTAssertFalse(first.isNew)
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(assembly.localMessageIDs, ["assistant-long"])
    }

    func testTrailingSplitDoesNotCreateAnEmptyBubble() {
        var assembly = ChatReplyStreamAssembly(rootMessageID: "assistant-local")
        _ = assembly.messageIDForIncomingText()
        assembly.receiveSplit()

        XCTAssertEqual(assembly.localMessageIDs, ["assistant-local"])
    }
}
