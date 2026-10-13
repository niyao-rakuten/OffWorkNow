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
        XCTAssertEqual(work.state, .before); XCTAssertEqual(work.totalSeconds, 8 * 3600)
        XCTAssertEqual(work.remaining, 9.5 * 3600)
        XCTAssertEqual(work.end, helper.date("2026-10-12 19:30:00"))
        XCTAssertEqual(ScheduleCalculator.snapshot(now: helper.date("2026-10-13 10:00:00"), settings: s).end, helper.date("2026-10-13 18:00:00"))
        let later = helper.date("2026-10-12 15:00:00"), w = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 15:00:00"), settings: s)
        XCTAssertEqual(w.workedSeconds, 3.5 * 3600)
        XCTAssertEqual(Money.formatted(EarningsCalculator.calculate(now: later, settings: s, work: w).earned!), "¥437.50")
        XCTAssertEqual(s.startMinute(on: helper.date("2026-10-13 10:00:00")), 540)
    }
    func testFlexibleStartInsideAndAfterLunchOnlySubtractsOverlap() throws {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 12 * 60 + 30
        XCTAssertNoThrow(try s.validated())
        let lunch = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 12:45:00"), settings: s)
        XCTAssertEqual(lunch.state, .lunch); XCTAssertEqual(lunch.workedSeconds, 0); XCTAssertEqual(lunch.totalSeconds, 8.5 * 3600)
        s.dailyStartMinutes["2026-10-12"] = 13 * 60 + 30
        let after = ScheduleCalculator.snapshot(now: helper.date("2026-10-12 15:00:00"), settings: s)
        XCTAssertEqual(after.totalSeconds, 9 * 3600); XCTAssertEqual(after.workedSeconds, 1.5 * 3600)
    }
    func testFlexibleDateValidationPersistenceAndDefaultReset() throws {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 600
        XCTAssertEqual(try SettingsCodec.decode(JSONEncoder().encode(s)).dailyStartMinutes["2026-10-12"], 600)
        s.dailyStartMinutes.removeValue(forKey: "2026-10-12")
        XCTAssertEqual(s.startMinute(on: helper.date("2026-10-12 10:00:00")), 540)
        s.dailyStartMinutes["2026-02-30"] = 600; XCTAssertThrowsError(try s.validated())
        s.dailyStartMinutes = ["2026-10-12":900]; XCTAssertThrowsError(try s.validated())
        s.dailyStartMinutes = ["2026-10-12":-1]; XCTAssertThrowsError(try s.validated())
    }
    func testFlexibleStartChangesHourlyAndOffworkReminders() {
        var s = helper.settings(); s.dailyStartMinutes["2026-10-12"] = 630
        let before = helper.date("2026-10-12 09:00:00")
        XCTAssertNil(ReminderPlanner.startupEvent(now: before, settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertEqual(ReminderPlanner.next(now: before, settings: s, ledger: ReminderLedger(), pause: nil)?.date, helper.date("2026-10-12 11:00:00"))
        let offwork = ReminderPlanner.next(now: helper.date("2026-10-12 19:00:01"), settings: s, ledger: ReminderLedger(), pause: nil)!
        XCTAssertEqual(offwork.kind, .offwork); XCTAssertEqual(offwork.date, helper.date("2026-10-12 19:30:00"))
    }
    func testEarlierStartAndOvertimeFollowDailyEnd() {
        var s = helper.settings(); s.overtimeEnabled = true
        s.dailyStartMinutes["2026-10-12"] = 8 * 60
        let now = helper.date("2026-10-12 16:00:00")
        let work = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(work.end, helper.date("2026-10-12 17:00:00"))
        XCTAssertEqual(work.remaining, 3600)
        XCTAssertEqual(DisplayFormatter.menu(settings: s, work: work, earnings: EarningsCalculator.calculate(now: now, settings: s, work: work)), "下班 01:00")
        s.dailyStartMinutes["2026-10-12"] = 630
        let later = helper.date("2026-10-12 18:30:00")
        let laterWork = ScheduleCalculator.snapshot(now: later, settings: s)
        XCTAssertEqual(laterWork.state, .working)
        XCTAssertFalse(OvertimeCalculator.snapshot(now: later, settings: s, work: laterWork, checkout: nil).isOvertime)
        let event = OvertimeCalculator.next(now: helper.date("2026-10-12 19:30:01"), settings: s, checkout: nil, ledger: ReminderLedger())!
        XCTAssertEqual(event.date, helper.date("2026-10-12 19:35:00"))
        XCTAssertTrue(ReminderPlanner.due(event, now: event.date, settings: s, ledger: ReminderLedger(), pause: nil))
        s.dailyStartMinutes.removeValue(forKey: "2026-10-12")
        XCTAssertEqual(s.endMinute(on: now), 18 * 60)
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
    func testDurationIsOnlyPersistedShiftLengthAndMigratesLegacySettings() throws {
        let legacy = Data(#"{"startMinute":540,"endMinute":1110,"dailyStartMinutes":{"2026-10-12":630}}"#.utf8)
        var settings = try SettingsCodec.decode(legacy)
        XCTAssertEqual(settings.workDurationMinutes, 570)
        let now = helper.date("2026-10-12 15:00:00")
        XCTAssertEqual(settings.endMinute(on: now), 1200)
        settings.startMinute = 480
        XCTAssertEqual(settings.endMinute(on: now), 1200, "A dated start and duration must not depend on the default start")
        settings.workDurationMinutes = 480
        let snapshot = ScheduleCalculator.snapshot(now: now, settings: settings)
        XCTAssertEqual(snapshot.end, helper.date("2026-10-12 18:30:00"))
        XCTAssertEqual(snapshot.remaining, 3.5 * 3600)
        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["endMinute"])
        XCTAssertEqual(object["workDurationMinutes"] as? Int, 480)
        XCTAssertEqual(try SettingsCodec.decode(encoded), settings)
        XCTAssertThrowsError(try SettingsCodec.decode(Data(#"{"endMinute":"invalid"}"#.utf8)))
    }
    func testDurationValidationRejectsZeroAndCrossDayShift() {
        var settings = helper.settings()
        settings.workDurationMinutes = 0
        XCTAssertThrowsError(try settings.validated())
        settings.workDurationMinutes = 540
        settings.dailyStartMinutes["2026-10-12"] = 900
        XCTAssertThrowsError(try settings.validated())
    }
    func testMigrationKeepsNineAndFiveMinuteDefaults() throws {
        let s = try SettingsCodec.decode(Data("{}".utf8))
        XCTAssertEqual(s.startMinute, 540); XCTAssertEqual(s.overtimeIntervalMinutes, 5); XCTAssertTrue(s.dailyStartMinutes.isEmpty)
    }
}
