import XCTest
@testable import WorkdayCore

final class OvertimeTests: ChineseLocalizationTestCase {
    func testLocalizedDurationOmitsZeroHours() {
        for (seconds, chinese, english) in [(0.0, "0分钟", "0min"), (300, "5分钟", "5min"), (3600, "1小时0分钟", "1h0min"), (3900, "1小时5分钟", "1h5min")] {
            XCTAssertEqual(OvertimeCalculator.duration(seconds, language: .simplifiedChinese), chinese)
            XCTAssertEqual(OvertimeCalculator.duration(seconds, language: .english), english)
            XCTAssertTrue(OvertimeCalculator.message(seconds: seconds, language: .english).contains(english))
        }
    }
    let helper = CalculationTests()
    func settings() -> WorkSettings { var s = helper.settings(); s.overtimeEnabled = true; return s }
    func snapshot(_ time: String, checkout: CheckoutRecord? = nil) -> CheckoutSnapshot {
        let s = settings(), now = helper.date("2026-10-12 " + time)
        return OvertimeCalculator.snapshot(now: now, settings: s, work: ScheduleCalculator.snapshot(now: now, settings: s), checkout: checkout)
    }
    func testCheckoutEligibilityAndOvertimeBoundaries() {
        XCTAssertFalse(snapshot("08:59:59").canCheckout)
        XCTAssertTrue(snapshot("09:00:00").canCheckout)
        XCTAssertFalse(snapshot("18:00:00").isOvertime)
        XCTAssertEqual(snapshot("18:00:01").overtimeSeconds, 1)
        XCTAssertEqual(snapshot("19:10:00").duration, "1小时10分钟")
        let s = settings(), rest = helper.date("2026-10-17 19:00:00")
        let state = OvertimeCalculator.snapshot(now: rest, settings: s, work: ScheduleCalculator.snapshot(now: rest, settings: s), checkout: nil)
        XCTAssertFalse(state.canCheckout); XCTAssertFalse(state.isOvertime)
    }
    func testCheckoutFreezesOvertimeAndResetsNextDay() throws {
        let s = settings(); let record = CheckoutRecord(now: helper.date("2026-10-12 18:12:00"), settings: s)
        let persisted = try JSONDecoder().decode(CheckoutRecord.self, from: JSONEncoder().encode(record))
        XCTAssertTrue(snapshot("19:00:00", checkout: persisted).isCheckedOut)
        XCTAssertFalse(snapshot("19:00:00", checkout: persisted).isOvertime)
        XCTAssertEqual(snapshot("19:00:00", checkout: persisted).overtimeSeconds, 720)
        XCTAssertFalse(snapshot("19:00:00", checkout: persisted).canCheckout)
        XCTAssertFalse(record.applies(now: helper.date("2026-10-13 09:00:00"), settings: s))
        var another = s; another.timeZoneID = "America/New_York"
        XCTAssertFalse(record.applies(now: helper.date("2026-10-12 19:00:00"), settings: another))
    }
    func testEarlyCheckoutHasNoOvertimeAndFutureRecordNotApplied() {
        let record = CheckoutRecord(now: helper.date("2026-10-12 15:00:00"), settings: settings())
        XCTAssertEqual(snapshot("19:00:00", checkout: record).overtimeSeconds, 0)
        XCTAssertFalse(snapshot("14:00:00", checkout: record).isCheckedOut)
    }
    func testFirstReminderAtFiveMinutesThenEveryFiveMinutes() {
        let s = settings(), ledger = ReminderLedger()
        let first = OvertimeCalculator.next(now: helper.date("2026-10-12 17:00:00"), settings: s, checkout: nil, ledger: ledger)!
        XCTAssertEqual(first.date, helper.date("2026-10-12 18:05:00")); XCTAssertEqual(first.id, "overtime.Asia/Shanghai.2026-10-12.300")
        let second = OvertimeCalculator.next(now: helper.date("2026-10-12 18:05:00"), settings: s, checkout: nil, ledger: ledger)!
        XCTAssertEqual(second.date, helper.date("2026-10-12 18:10:00"))
        let late = OvertimeCalculator.next(now: helper.date("2026-10-12 19:12:00"), settings: s, checkout: nil, ledger: ledger)!
        XCTAssertEqual(late.date, helper.date("2026-10-12 19:15:00"))
    }
    func testAlternatingRequestedCopyAndHourFormat() {
        XCTAssertEqual(OvertimeCalculator.message(seconds: 300), "你怎么又在加班？已经加班5分钟了")
        XCTAssertEqual(OvertimeCalculator.message(seconds: 600), "已经加班10分钟！不要再当牛马了，快点下班")
        XCTAssertEqual(OvertimeCalculator.message(seconds: 3900), "你怎么又在加班？已经加班1小时5分钟了")
        XCTAssertEqual(OvertimeCalculator.message(seconds: 4200), "已经加班1小时10分钟！不要再当牛马了，快点下班")
    }
    func testCheckoutCancelsTodayEventsAndResumesTomorrow() {
        let s = settings(), now = helper.date("2026-10-12 15:00:00")
        let record = CheckoutRecord(now: now, settings: s)
        let next = ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: nil, checkout: record)!
        XCTAssertEqual(next.date, helper.date("2026-10-13 09:00:00"))
        XCTAssertNil(OvertimeCalculator.next(now: helper.date("2026-10-12 19:00:00"), settings: s, checkout: record, ledger: ReminderLedger()))
        let offwork = ReminderPlanner.event(date: helper.date("2026-10-12 18:00:00"), kind: .offwork, settings: s)
        XCTAssertFalse(ReminderPlanner.due(offwork, now: offwork.date, settings: s, ledger: ReminderLedger(), pause: nil, checkout: record))
    }
    func testClockJumpDedupAndLateCheckoutCancelsQueuedReminder() throws {
        let s = settings(), now = helper.date("2026-10-12 18:00:00")
        let event = OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: ReminderLedger())!
        XCTAssertTrue(ReminderPlanner.due(event, now: event.date, settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertFalse(ReminderPlanner.due(event, now: helper.date("2026-10-12 19:01:00"), settings: s, ledger: ReminderLedger(), pause: nil))
        var ledger = ReminderLedger(); ledger.consume(event)
        let restored = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(OvertimeCalculator.next(now: now, settings: s, checkout: nil, ledger: restored)?.date, helper.date("2026-10-12 18:10:00"))
        let record = CheckoutRecord(now: event.date.addingTimeInterval(1), settings: s)
        XCTAssertFalse(ReminderPlanner.due(event, now: event.date.addingTimeInterval(2), settings: s, ledger: ReminderLedger(), pause: nil, checkout: record))
    }
    func testNoOvertimeOnRestDayAfterMidnightOrWhenDisabled() {
        var s = settings()
        XCTAssertNil(OvertimeCalculator.next(now: helper.date("2026-10-12 23:59:59"), settings: s, checkout: nil, ledger: ReminderLedger()))
        XCTAssertNil(OvertimeCalculator.next(now: helper.date("2026-10-17 19:00:00"), settings: s, checkout: nil, ledger: ReminderLedger()))
        s.overtimeEnabled = false
        XCTAssertNil(OvertimeCalculator.next(now: helper.date("2026-10-12 19:00:00"), settings: s, checkout: nil, ledger: ReminderLedger()))
    }
    func testOvertimeIndependentFromHourlyPauseAndNoOvertimePay() {
        var s = settings(); s.hourlyEnabled = false; s.offworkEnabled = false
        let now = helper.date("2026-10-12 18:00:00")
        let pause = ReminderPause(until: helper.date("2026-10-12 23:00:00"), dateKey: "2026-10-12")
        let event = ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: pause)!
        XCTAssertEqual(event.kind, .overtime); XCTAssertEqual(event.date, helper.date("2026-10-12 18:05:00"))
        let work = ScheduleCalculator.snapshot(now: event.date, settings: s)
        XCTAssertEqual(EarningsCalculator.calculate(now: event.date, settings: s, work: work).earned, 1000)
    }
    func testOldSettingsAcquireNewDefaults() throws {
        let value = try SettingsCodec.decode(Data(#"{"schemaVersion":1,"timeZoneID":"Asia/Shanghai"}"#.utf8))
        XCTAssertTrue(value.overtimeEnabled); XCTAssertTrue(value.petEnabled); XCTAssertEqual(value.petKind, .cat)
        XCTAssertEqual(value.timeZoneID, "Asia/Shanghai")
    }
}
