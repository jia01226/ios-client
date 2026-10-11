import XCTest
@testable import KeApp

@MainActor
final class MomentsDraftStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MomentsDraftTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testDraftRestoresTextPhotoUploadedURLAndEditingTextAfterRecreation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MomentsDraftStore(scope: "test1", rootDirectory: root)
        first.text = "还没发布的话"
        first.imageData = Data([1, 2, 3, 4])
        first.uploadedImage = "/uploads/draft.jpg"
        first.textDrafts = ["comment-701": "还没发送的评论", "edit-702": "编辑到一半"]

        let restored = MomentsDraftStore(scope: "test1", rootDirectory: root)
        XCTAssertEqual(restored.text, first.text)
        XCTAssertEqual(restored.imageData, Data([1, 2, 3, 4]))
        XCTAssertEqual(restored.uploadedImage, "/uploads/draft.jpg")
        XCTAssertEqual(restored.textDrafts, first.textDrafts)
        XCTAssertNil(restored.persistenceError)

        restored.imageData = Data([5, 6])
        let replaced = MomentsDraftStore(scope: "test1", rootDirectory: root)
        XCTAssertEqual(replaced.imageData, Data([5, 6]))
        XCTAssertTrue(replaced.uploadedImage.isEmpty, "Changing the photo must invalidate the previous uploaded URL")
    }

    func testConfirmedPublicationClearsPostAndPhotoButKeepsOtherUnsentComments() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MomentsDraftStore(scope: "test1", rootDirectory: root)
        store.text = "已发布"
        store.imageData = Data([1, 2, 3])
        store.uploadedImage = "/uploads/published.jpg"
        store.textDrafts["comment-701"] = "继续留着"
        store.clearPost()

        let restored = MomentsDraftStore(scope: "test1", rootDirectory: root)
        XCTAssertTrue(restored.text.isEmpty)
        XCTAssertNil(restored.imageData)
        XCTAssertTrue(restored.uploadedImage.isEmpty)
        XCTAssertEqual(restored.textDrafts["comment-701"], "继续留着")
        restored.textDrafts["comment-701"] = nil
        XCTAssertTrue(MomentsDraftStore(scope: "test1", rootDirectory: root).textDrafts.isEmpty)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        let remainingFiles = files.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        XCTAssertTrue(remainingFiles.isEmpty)
        // A crash during cleanup can leave a photo file; no manifest means no draft.
        let scopeDirectories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let scopeDirectory = try XCTUnwrap(scopeDirectories.first)
        try Data([9, 9]).write(to: scopeDirectory.appendingPathComponent("orphan.jpg"))
        XCTAssertNil(MomentsDraftStore(scope: "test1", rootDirectory: root).imageData)
    }

    func testScopesKeepIndependentDraftsIncludingSimilarPathLikeNames() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MomentsDraftStore(scope: "test/1", rootDirectory: root)
        let second = MomentsDraftStore(scope: "test_1", rootDirectory: root)
        first.text = "第一条线路"
        first.imageData = Data([1])
        second.text = "另一条线路"
        second.textDrafts["comment-1"] = "不同的评论"
        first.clearPost()

        let restoredFirst = MomentsDraftStore(scope: "test/1", rootDirectory: root)
        let restoredSecond = MomentsDraftStore(scope: "test_1", rootDirectory: root)
        XCTAssertTrue(restoredFirst.text.isEmpty)
        XCTAssertNil(restoredFirst.imageData)
        XCTAssertTrue(restoredFirst.textDrafts.isEmpty)
        XCTAssertEqual(restoredSecond.text, "另一条线路")
        XCTAssertEqual(restoredSecond.textDrafts["comment-1"], "不同的评论")
    }
}
