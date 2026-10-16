import XCTest
@testable import WorkdayCore
final class LocalIntentTests: XCTestCase {
    let bot = AIBot()
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10))! }
    func testDietAndSummaryRouting() {
        guard case .diet(let text, _) = bot.interpret("我今天吃了鸡蛋，喝了牛奶", now: now, calendar: calendar) else { return XCTFail() }
        XCTAssertEqual(text, "我今天吃了鸡蛋，喝了牛奶")
        guard case .dietSummary = bot.interpret("统计今天的饮食", now: now) else { return XCTFail() }
        XCTAssertNil(bot.interpret("我应该吃什么？", now: now))
        guard case .dietSummary = bot.interpret("我今天吃了什么？", now: now) else { return XCTFail() }
        XCTAssertNil(bot.interpret("我今天吃了辣椒会怎样？", now: now))
        XCTAssertNil(bot.interpret("解释一下 Swift", now: now))
    }
    func testReminderDatesAndValidation() {
        guard case .reminder(let title, let date) = bot.interpret("提醒我14:00创建 App Connect 新版本", now: now, calendar: calendar) else { return XCTFail() }
        XCTAssertEqual(title, "创建 App Connect 新版本")
        XCTAssertEqual(calendar.component(.hour, from: date), 14)
        for input in ["提醒我09:00回归测试", "提醒我25:00回归测试", "提醒我回归测试"] {
            guard case .clarification = bot.interpret(input, now: now, calendar: calendar) else { return XCTFail(input) }
        }
        guard case .reminder(_, let tomorrow) = bot.interpret("提醒我明天下午4点回归测试", now: now, calendar: calendar) else { return XCTFail() }
        XCTAssertEqual(calendar.component(.day, from: tomorrow), 17)
        XCTAssertEqual(calendar.component(.hour, from: tomorrow), 16)
    }
    func testChecklistAndPersistence() throws {
        for text in ["帮我创建一个 todo checklist", "帮我建一个 todo list", "帮我建一个 checklist", "today todo", "Today todo list", "今天待办", "create a checklist"] {
            XCTAssertEqual(bot.interpret(text, now: now), .checklist([]), text)
        }
        XCTAssertEqual(bot.interpret("创建待办清单：发布版本、回归测试", now: now), .checklist(["发布版本", "回归测试"]))
        var todo = BotTodo(text: "回归测试", due: now); todo.done = true
        XCTAssertEqual(try JSONDecoder().decode(BotTodo.self, from: JSONEncoder().encode(todo)), todo)
    }
}
