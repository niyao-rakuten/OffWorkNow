import XCTest
@testable import WorkdayCore

final class AssistantHistoryTests: XCTestCase {
    func testRoundTripPreservesUnicodeAndPartialReply() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let messages = [AssistantMessage(role: .user, content: "你好\n小宠物 🐈"), AssistantMessage(role: .assistant, content: "Hi 主人", complete: false)]
        try AssistantHistory.save(messages, to: url)
        let loaded = try AssistantHistory.load(from: url)
        XCTAssertEqual(loaded.map(\.id), messages.map(\.id))
        XCTAssertEqual(loaded.map(\.content), messages.map(\.content))
        XCTAssertFalse(loaded[1].complete)
        try AssistantHistory.save(loaded + [AssistantMessage(role: .user, content: "再聊聊")], to: url)
        XCTAssertEqual(try AssistantHistory.load(from: url).count, 3)
    }
    func testCorruptHistoryThrowsRatherThanSilentlyDiscarding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try AssistantHistory.load(from: url))
    }
}
