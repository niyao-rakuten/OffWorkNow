import XCTest
@testable import WorkdayCore
final class ChecklistCarryoverTests: ChineseLocalizationTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))! }
    private func history() -> [AssistantMessage] {
        var done = BotTodo(text: "Write report"); done.done = true
        var yesterday = AssistantMessage(role: .assistant, content: "checklist", date: calendar.date(byAdding: .day, value: -1, to: now)!)
        yesterday.checklist = BotChecklist(items: [done, BotTodo(text: "Review PR"), BotTodo(text: "Fix bug")])
        var recall = yesterday
        recall = AssistantMessage(role: .assistant, content: "recalled", date: yesterday.date)
        recall.checklist = yesterday.checklist
        return [yesterday, recall]
    }
    private func offer(in messages: inout [AssistantMessage]) -> UUID {
        var greeting = AssistantMessage(role: .assistant, content: "Hi", proactive: true, date: now)
        greeting.carryover = AssistantHistory.carryoverOffer(messages, now: now, calendar: calendar)
        messages.append(greeting)
        return greeting.id
    }
    func testCarriesOnlyYesterdayUnfinishedAndCreatesIndependentChecklistOnce() throws {
        var messages = history()
        let id = offer(in: &messages)
        XCTAssertEqual(messages.last?.carryover?.items.map(\.text), ["Review PR", "Fix bug"])
        XCTAssertTrue(AssistantHistory.answerCarryover(&messages, messageID: id, accept: true, now: now, calendar: calendar))
        let created = try XCTUnwrap(messages.last?.checklist)
        XCTAssertEqual(created.items.map(\.text), ["Review PR", "Fix bug"])
        XCTAssertTrue(created.items.allSatisfy { !$0.done && $0.due == nil && $0.originID != nil })
        XCTAssertFalse(AssistantHistory.answerCarryover(&messages, messageID: id, accept: true, now: now, calendar: calendar))
        AssistantHistory.updateChecklist(&messages, messageID: messages.last!.id) { $0.items[0].done = true }
        XCTAssertFalse(messages[0].checklist!.items[1].done)
        let restored = try JSONDecoder().decode([AssistantMessage].self, from: JSONEncoder().encode(messages))
        XCTAssertEqual(restored, messages)
        XCTAssertEqual(restored.first(where: { $0.id == id })?.carryover?.accepted, true)
    }
    func testDeclinePersistsWithoutCreatingOrDeletingTasks() {
        var messages = history(); let id = offer(in: &messages); let count = messages.count
        XCTAssertTrue(AssistantHistory.answerCarryover(&messages, messageID: id, accept: false, now: now, calendar: calendar))
        XCTAssertEqual(messages.count, count)
        XCTAssertFalse(AssistantHistory.answerCarryover(&messages, messageID: id, accept: true, now: now, calendar: calendar))
        XCTAssertEqual(messages[0].checklist?.items.count, 3)
    }
    func testRechecksCompletedTasksAndRejectsExpiredOffer() {
        var messages = history(); let id = offer(in: &messages)
        AssistantHistory.updateChecklist(&messages, messageID: messages[0].id) { $0.items[1].done = true }
        XCTAssertTrue(AssistantHistory.answerCarryover(&messages, messageID: id, accept: true, now: now, calendar: calendar))
        XCTAssertEqual(messages.last?.checklist?.items.map(\.text), ["Fix bug"])
        var expired = history(); let expiredID = offer(in: &expired)
        XCTAssertFalse(AssistantHistory.answerCarryover(&expired, messageID: expiredID, accept: true, now: now.addingTimeInterval(86400), calendar: calendar))
        XCTAssertNil(AssistantHistory.carryoverOffer(history(), now: now.addingTimeInterval(86400), calendar: calendar))
    }
    func testCheckoutIncludesTaskSnapshotAndDuplicateOffersDoNotDuplicateTasks() throws {
        var messages = history(); let firstID = offer(in: &messages); let secondID = offer(in: &messages)
        XCTAssertTrue(AssistantHistory.answerCarryover(&messages, messageID: firstID, accept: true, now: now, calendar: calendar))
        XCTAssertTrue(AssistantHistory.answerCarryover(&messages, messageID: secondID, accept: true, now: now, calendar: calendar))
        XCTAssertEqual(AssistantHistory.checklistItems(messages, on: now, calendar: calendar).count, 2)
        let helper = CalculationTests()
        let date = helper.date("2026-10-12 18:00:00")
        var done = BotTodo(text: "Ship feature"); done.done = true
        let context = AIBotContext(now: date, settings: helper.settings(), checklistItems: [done, BotTodo(text: "Review PR")])
        let output = AIBot().handle(.checkout, in: context).compactMap { action -> AIBotMessage? in
            if case .postMessage(let message) = action { return message }; return nil
        }
        let english = try XCTUnwrap(output.first).text(language: .english).body
        XCTAssertTrue(english.contains("Completed today: Ship feature."))
        XCTAssertTrue(english.contains("Still unfinished: Review PR."))
        var greeting = messages[2]
        greeting.localizedContents = ["zh-Hans": "早上好", "en": "Good morning"]
        UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
        XCTAssertTrue(greeting.displayedContent.contains("unfinished tasks from yesterday"))
        XCTAssertFalse(greeting.displayedContent.contains("昨日"))
    }
    func testPromptAndSummaryLocalizeWithoutTranslatingUserTasksAndLegacyReportsDecode() throws {
        let prompt = try XCTUnwrap(AssistantHistory.carryoverOffer(history(), now: now, calendar: calendar))
        XCTAssertTrue(prompt.prompt(language: .simplifiedChinese).contains("1. Review PR\n2. Fix bug"))
        XCTAssertNil(prompt.prompt(language: .english).range(of: "\\p{Han}", options: .regularExpression))
        var report = DailyReportTests().report()
        report.checklistItems = AssistantHistory.checklistItems(history(), on: now.addingTimeInterval(-86400), calendar: calendar)
        XCTAssertTrue(report.taskSummary(language: .simplifiedChinese)!.contains("今天已完成：Write report。"))
        XCTAssertTrue(report.taskSummary(language: .english)!.contains("Still unfinished: Review PR, Fix bug"))
        XCTAssertTrue(report.assistantReport(hideEarnings: true, language: .english).contains("Completed today: Write report."))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        json.removeValue(forKey: "checklistItems")
        let old = try JSONDecoder().decode(DailyReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.checklistItems)
        XCTAssertNil(old.taskSummary())
    }
}
