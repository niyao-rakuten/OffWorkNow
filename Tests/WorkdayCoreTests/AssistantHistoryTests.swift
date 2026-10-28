import XCTest
@testable import WorkdayCore

final class AssistantHistoryTests: XCTestCase {
    func testRoundTripPreservesUnicodeAndPartialReply() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let messages = [AssistantMessage(role: .user, content: "你好\n精灵 🐈"), AssistantMessage(role: .assistant, content: "Hi 主人", complete: false)]
        try AssistantHistory.save(messages, to: url)
        let loaded = try AssistantHistory.load(from: url)
        XCTAssertEqual(loaded.map(\.id), messages.map(\.id))
        XCTAssertEqual(loaded.map(\.content), messages.map(\.content))
        XCTAssertFalse(loaded[1].complete)
        try AssistantHistory.save(loaded + [AssistantMessage(role: .user, content: "再聊聊")], to: url)
        XCTAssertEqual(try AssistantHistory.load(from: url).count, 3)
    }
    func testChecklistSortingAndSharedCopiesPersist() throws {
        let a = BotTodo(text: "A")
        var b = BotTodo(text: "B"); b.done = true
        let c = BotTodo(text: "C")
        let checklist = BotChecklist(items: [b, a, c])
        var first = AssistantMessage(role: .assistant, content: "tasks")
        first.checklist = checklist
        var copy = AssistantMessage(role: .assistant, content: "same tasks")
        copy.checklist = checklist
        var messages = [first, copy]
        XCTAssertEqual(checklist.orderedItems.map(\.id), [a.id, c.id, b.id])
        AssistantHistory.updateChecklist(&messages, messageID: first.id) { $0.moveItem(c.id, to: a.id) }
        XCTAssertEqual(messages[0].checklist?.items.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(messages[0].checklist, messages[1].checklist)
        AssistantHistory.updateChecklist(&messages, messageID: first.id) { $0.moveItem(b.id, to: c.id) }
        XCTAssertEqual(messages[0].checklist?.items.map(\.id), [c.id, a.id, b.id])
        AssistantHistory.updateChecklist(&messages, messageID: first.id) { $0.items[0].done = true }
        XCTAssertEqual(messages[0].checklist?.items.map(\.id), [a.id, c.id, b.id])
        AssistantHistory.updateChecklist(&messages, messageID: first.id) { $0.items[2].done = false }
        XCTAssertEqual(messages[0].checklist?.items.map(\.id), [a.id, b.id, c.id])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try AssistantHistory.save(messages, to: url)
        XCTAssertEqual(try AssistantHistory.load(from: url).map(\.checklist), messages.map(\.checklist))
    }
    func testCorruptHistoryThrowsRatherThanSilentlyDiscarding() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try AssistantHistory.load(from: url))
    }
}
