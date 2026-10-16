import XCTest
@testable import WorkdayCore

final class AssistantTimelineTests: ChineseLocalizationTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func messages(_ day: String) -> [AssistantMessage] {
        [.init(role: .user, content: "u-" + day, date: date(day + "T03:00:00Z")),
         .init(role: .assistant, content: "a-" + day, date: date(day + "T03:01:00Z"))]
    }
    func testDefaultTodayAndDayPaginationHaveUniqueChronologicalSections() {
        let now = date("2026-10-16T08:00:00Z")
        let history = messages("2026-10-14") + messages("2026-10-12") + messages("2026-10-16") + messages("2026-10-17")
        let today = AssistantTimeline.sections(history, now: now, calendar: calendar, earlierDays: 0)
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today[0].messages.count, 2)
        let loaded = AssistantTimeline.sections(history, now: now, calendar: calendar, earlierDays: 2)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map { calendar.component(.day, from: $0.date) }, [12, 14, 16])
        XCTAssertEqual(Set(loaded.map(\.id)).count, 3)
        XCTAssertEqual(AssistantTimeline.earlierDayCount(history, now: now, calendar: calendar), 2)
    }
    func testTimezoneBoundaryAndContextCannotLeakEarlierOrFutureDays() throws {
        let now = date("2026-10-15T16:01:00Z") // Oct 16 in Shanghai
        let history = [AssistantMessage(role: .user, content: "yesterday", date: date("2026-10-15T15:59:00Z")),
                       AssistantMessage(role: .assistant, content: "cross-midnight reply", date: now)]
            + messages("2026-10-16") + messages("2026-10-17")
            + [AssistantMessage(role: .assistant, content: "old greeting", proactive: true, date: date("2026-10-14T00:00:00Z"))]
        let context = try AssistantContext.build(history: history, system: "s", current: "c", now: now, calendar: calendar)
        let text = context.compactMap { if case .string(let s) = $0.content { return s }; return nil }
        XCTAssertEqual(text, ["s", "u-2026-10-16", "a-2026-10-16", "c"])
        let tomorrow = date("2026-10-16T16:01:00Z")
        XCTAssertEqual(AssistantTimeline.today(history, now: tomorrow, calendar: calendar).map(\.content), ["u-2026-10-17", "a-2026-10-17"])
    }
    func testEmptyTodayStillAllowsPreviousDayAndDateLabelsLocalize() {
        let now = date("2026-10-16T08:00:00Z"), history = messages("2026-10-14")
        XCTAssertTrue(AssistantTimeline.sections(history, now: now, calendar: calendar, earlierDays: 0).isEmpty)
        XCTAssertEqual(AssistantTimeline.sections(history, now: now, calendar: calendar, earlierDays: 1).count, 1)
        XCTAssertEqual(AssistantTimeline.dateLabel(now, calendar: calendar, language: .simplifiedChinese), "2026年10月16日 星期五")
        XCTAssertTrue(AssistantTimeline.dateLabel(now, calendar: calendar, language: .english).contains("Friday"))
    }
    func testDailyGreetingOnlyPostsOnceAndLegacyDuplicatesAreHidden() {
        let now = date("2026-10-16T08:00:00Z")
        let key = AssistantGreetingPolicy.dayKey(now: now, calendar: calendar)
        XCTAssertTrue(AssistantGreetingPolicy.shouldPost(messages: [], lastPostedDay: nil, now: now, calendar: calendar))
        XCTAssertFalse(AssistantGreetingPolicy.shouldPost(messages: [], lastPostedDay: key, now: now, calendar: calendar))
        let first = AssistantMessage(role: .assistant, content: "又是新的一天", proactive: true, date: now)
        let repeated = AssistantMessage(role: .assistant, content: "又是新的一天", proactive: true, date: now.addingTimeInterval(60))
        XCTAssertFalse(AssistantGreetingPolicy.shouldPost(messages: [first], lastPostedDay: nil, now: now, calendar: calendar))
        XCTAssertEqual(AssistantTimeline.today([first, repeated], now: now, calendar: calendar).map(\.id), [first.id])
        XCTAssertEqual(AssistantTimeline.sections([first, repeated], now: now, calendar: calendar, earlierDays: 0)[0].messages.count, 1)
        let tomorrow = now.addingTimeInterval(86400)
        XCTAssertTrue(AssistantGreetingPolicy.shouldPost(messages: [first], lastPostedDay: key, now: tomorrow, calendar: calendar))
    }
    func testChecklistMessagePersistsIndependentlyAndContextIncludesCheckedItems() throws {
        var first = AssistantMessage(role: .assistant, content: "Your checklist is ready.", proactive: true)
        first.checklist = BotChecklist(items: [BotTodo(text: "App Connect")])
        first.checklist?.items[0].done = true
        var second = AssistantMessage(role: .assistant, content: "Another list", proactive: true)
        second.checklist = BotChecklist()
        let decoded = try JSONDecoder().decode([AssistantMessage].self, from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(decoded, [first, second])
        XCTAssertTrue(decoded[1].checklist!.items.isEmpty)
        XCTAssertTrue(decoded[0].contextContent.contains("- [x] App Connect"))
        XCTAssertNotEqual(first.checklist!.id, second.checklist!.id)
    }
}
