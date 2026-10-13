import XCTest
@testable import WorkdayCore

final class FlexibleScheduleTests: XCTestCase {
    let helper = CalculationTests()
    func testDefaultNineAndDailyStartChangesOnlyOneDay() throws {
        var s = helper.settings(); let now = helper.date("2026-10-12 10:00:00")
        XCTAssertEqual(s.startMinute(on: now), 540)
        s.dailyStartMinutes["2026-10-12"] = 630
        XCTAssertNoThrow(try s.validated())
        let work = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(work.state, .before); XCTAssertEqual(work.totalSeconds, 6.5 * 3600)
        XCTAssertEqual(work.remaining, 8 * 3600)
        let later = helper.date("2026-10-12 15:00:00"), w = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 15:00:00"), settings: s)
        XCTAssertEqual(w.workedSeconds, 3.5 * 3600)
        XCTAssertEqual(Money.formatted(EarningsCalculator.calculate(now: later, settings: s, work: w).earned!), "¥538.46")
        XCTAssertEqual(s.startMinute(on: helper.date("2026-10-13 10:00:00")), 540)
    }
    func testFlexibleStartInsideAndAfterLunchOnlySubtractsOverlap() throws {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 12 * 60 + 30
        XCTAssertNoThrow(try s.validated())
        let lunch = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 12:45:00"), settings: s)
        XCTAssertEqual(lunch.state, .lunch); XCTAssertEqual(lunch.workedSeconds, 0); XCTAssertEqual(lunch.totalSeconds, 5 * 3600)
        s.dailyStartMinutes["2026-10-12"] = 13 * 60 + 30
        let after = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 15:00:00"), settings: s)
        XCTAssertEqual(after.totalSeconds, 4.5 * 3600); XCTAssertEqual(after.workedSeconds, 1.5 * 3600)
    }
    func testFlexibleDateValidationPersistenceAndDefaultReset() throws {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 600
        XCTAssertEqual(try SettingsCodec.decode(JSONEncoder().encode(s)).dailyStartMinutes["2026-10-12"], 600)
        s.dailyStartMinutes.removeValue(forKey: "2026-10-12")
        XCTAssertEqual(s.startMinute(on: helper.date("2026-10-12 10:00:00")), 540)
        s.dailyStartMinutes["2026-02-30"] = 600; XCTAssertThrowsError(try s.validated())
        s.dailyStartMinutes = ["2026-10-12":1080]; XCTAssertThrowsError(try s.validated())
        s.dailyStartMinutes = ["2026-10-12":-1]; XCTAssertThrowsError(try s.validated())
    }
    func testFlexibleStartChangesHourlyRemindersAndKeepsOffwork() {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 630
        let before = helper.date("2026-10-12 09:00:00")
        XCTAssertNil(ReminderPlanner.startupEvent(now: before, settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertEqual(ReminderPlanner.next(now: before, settings: s, ledger: ReminderLedger(), pause: nil)?.date, helper.date("2026-10-12 11:00:00"))
        let offwork = ReminderPlanner.next(now: helper.date("2026-10-12 17:00:01"), settings: s, ledger: ReminderLedger(), pause: nil)!
        XCTAssertEqual(offwork.kind, .offwork); XCTAssertEqual(offwork.date, helper.date("2026-10-12 18:00:00"))
    }
    func testCustomOvertimeIntervalAndCopy() throws {
        var s = helper.settings(); s.overtimeEnabled = true; s.overtimeIntervalMinutes = 10
        let now = helper.date("2026-10-12 18:01:00")
        let next = OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: ReminderLedger())!
        XCTAssertEqual(next.date, helper.date("2026-10-12 18:10:00"))
        XCTAssertTrue(ReminderPlanner.due(next, now: next.date, settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertEqual(OvertimeCalculator.message(seconds: 600, intervalMinutes: 10), "你怎么又在加班？已经加班0h10min了")
        XCTAssertEqual(OvertimeCalculator.message(seconds: 1200, intervalMinutes: 10), "已经加班0h20min！不要再当牛马了，快点下班")
        XCTAssertEqual(try OvertimeCalculator.parseInterval(" 15 "), 15)
        for value in ["", "0", "-1", "1.5", "NaN", "241", "999999999999999999999999999"] { XCTAssertThrowsError(try OvertimeCalculator.parseInterval(value)) }
        s.overtimeIntervalMinutes = 0; XCTAssertThrowsError(try s.validated())
    }
    func testIntervalChangesReuseElapsedEventIDAndSkipPast() {
        var s = helper.settings(); s.overtimeEnabled = true
        let now = helper.date("2026-10-12 18:07:00")
        let oldTen = ReminderPlanner.event(date: helper.date("2026-10-12 18:10:00"), kind: .overtime, settings: s)
        s.overtimeIntervalMinutes = 10
        let ten = OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: ReminderLedger())!
        XCTAssertEqual(ten.id, oldTen.id)
        var ledger = ReminderLedger(); ledger.consume(ten)
        XCTAssertEqual(OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: ledger)?.date, helper.date("2026-10-12 18:20:00"))
        s.overtimeIntervalMinutes = 3
        XCTAssertEqual(OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: ReminderLedger())?.date, helper.date("2026-10-12 18:09:00"))
    }
    func testMigrationKeepsNineAndFiveMinuteDefaults() throws {
        let s = try SettingsCodec.decode(Data("{}".utf8))
        XCTAssertEqual(s.startMinute, 540); XCTAssertEqual(s.overtimeIntervalMinutes, 5); XCTAssertTrue(s.dailyStartMinutes.isEmpty)
    }
}
