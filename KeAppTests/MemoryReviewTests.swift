import XCTest
@testable import KeApp

@MainActor
final class MemoryReviewTests: XCTestCase {
    func testDirectionAndThresholdIgnoreShortAndDiagonalDrags() {
        XCTAssertEqual(ReviewGesture.action(x: 120, y: 10), .accept)
        XCTAssertEqual(ReviewGesture.action(x: -120, y: 10), .reject)
        XCTAssertEqual(ReviewGesture.action(x: 10, y: -120), .defer)
        XCTAssertNil(ReviewGesture.action(x: 99, y: 0))
        XCTAssertNil(ReviewGesture.action(x: 110, y: 110))
        XCTAssertEqual(ReviewGesture.action(x: 0, y: 150), .changed)
    }

    func testReviewBoundaryKeepsFactsAndExcludesBehaviorInstructions() {
        XCTAssertTrue(MemoryFactBoundary.isReviewableFact(key: "身体用药", value: "目前每天服用舍曲林 50mg"))
        XCTAssertTrue(MemoryFactBoundary.isReviewableFact(key: "喜好", value: "不喜欢太甜的饮料"))
        XCTAssertTrue(MemoryFactBoundary.isReviewableFact(key: "关系约定", value: "喊爸爸时，柯会回应"))
        XCTAssertFalse(MemoryFactBoundary.isReviewableFact(key: "服药提醒", value: "晚上十点吃药"))
        XCTAssertFalse(MemoryFactBoundary.isReviewableFact(key: "生活", value: "记得按时吃药"))
        XCTAssertFalse(MemoryFactBoundary.isReviewableFact(key: "生活", value: "早点睡"))
        XCTAssertFalse(MemoryFactBoundary.isReviewableFact(key: "待办", value: "明天预约复诊"))
        XCTAssertEqual(MemoryFactBoundary.shelfTitle(key: "当前用药与剂量"), "我的药")
        XCTAssertEqual(MemoryFactBoundary.shelfTitle(key: "身体状态"), "生活")
        XCTAssertEqual(MemoryFactBoundary.shelfTitle(key: "饮食偏好"), "我的喜好")
        XCTAssertEqual(MemoryFactBoundary.shelfTitle(key: "关系约定"), "关系")
    }
}
