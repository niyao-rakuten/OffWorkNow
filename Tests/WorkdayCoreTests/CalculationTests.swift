import XCTest
@testable import WorkdayCore

final class CalculationTests: XCTestCase {
    func settings() -> WorkSettings { var s = WorkSettings(); s.timeZoneID = "Asia/Shanghai"; s.monthlySalary = 21750; s.overtimeEnabled = false; return s }
    func date(_ text: String, zone: String = "Asia/Shanghai") -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: zone); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.date(from: text)!
    }
    func testAllRequiredSalaryExamples() {
        let s = settings()
        for (time, amount, state) in [("08:59:00", "0", WorkState.before), ("09:00:00", "0", .working), ("12:00:00", "375", .lunch), ("12:30:00", "375", .lunch), ("13:00:00", "375", .working), ("15:00:00", "625", .working), ("18:00:00", "1000", .after), ("19:00:00", "1000", .after)] {
            let now = date("2026-10-12 " + time); let w = ScheduleCalculator.snapshot(now: now, settings: s)
            let e = EarningsCalculator.calculate(now: now, settings: s, work: w)
            XCTAssertEqual(w.state, state, time); XCTAssertEqual(w.totalSeconds, 28800)
            XCTAssertEqual(e.daily, 1000); XCTAssertEqual(e.earned, Decimal(string: amount), time)
        }
        let now = date("2026-10-12 15:00:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(w.progress, 0.625); XCTAssertEqual(w.remaining, 10800)
    }
    func testLunchDisabledChangesPayButNotCountdown() {
        var s = settings(); let now = date("2026-10-12 12:30:00")
        let before = ScheduleCalculator.snapshot(now: now, settings: s); s.lunchEnabled = false
        let after = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(after.totalSeconds, 32400); XCTAssertEqual(after.workedSeconds, 12600); XCTAssertEqual(after.state, .working); XCTAssertEqual(before.remaining, after.remaining)
        XCTAssertNotEqual(EarningsCalculator.calculate(now: now, settings: s, work: after).earned, 375)
    }
    func testRestDayAndOverrides() {
        var s = settings(); let now = date("2026-10-17 15:00:00")
        let rest = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(rest.state, .rest); XCTAssertEqual(rest.progress, 0)
        XCTAssertEqual(EarningsCalculator.calculate(now: now, settings: s, work: rest).daily, 0)
        s.overrides["2026-10-17"] = true
        XCTAssertEqual(ScheduleCalculator.snapshot(now: now, settings: s).state, .working)
        s.overrides["2026-10-12"] = false
        XCTAssertEqual(ScheduleCalculator.snapshot(now: date("2026-10-12 09:00:00"), settings: s).state, .rest)
    }
    func testNextDayResets() {
        let s = settings(); let now = date("2026-10-13 08:59:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(w.workedSeconds, 0); XCTAssertEqual(EarningsCalculator.calculate(now: now, settings: s, work: w).earned, 0)
    }
    func testPlannedMonthLeapYearAndOverrides() {
        var s = settings(); s.payMode = .plannedDays
        XCTAssertEqual(ScheduleCalculator.plannedDays(now: date("2024-02-29 12:00:00"), settings: s), 21)
        s.overrides["2024-02-29"] = false; s.overrides["2024-02-24"] = true
        XCTAssertEqual(ScheduleCalculator.plannedDays(now: date("2024-02-01 12:00:00"), settings: s), 21)
        XCTAssertEqual(ScheduleCalculator.plannedDays(now: date("2024-03-01 12:00:00"), settings: s), 21)
        XCTAssertEqual(ScheduleCalculator.key(date("2024-02-29 23:59:59"), calendar: s.calendar), "2024-02-29")
        XCTAssertEqual(ScheduleCalculator.key(date("2024-03-01 00:00:00"), calendar: s.calendar), "2024-03-01")
    }
    func testZeroPlannedDaysGivesReason() {
        var s = settings(); s.payMode = .plannedDays; s.weekdays = [2]
        for d in [5,12,19,26] { s.overrides[String(format: "2026-10-%02d", d)] = false }
        let now = date("2026-10-12 15:00:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(ScheduleCalculator.plannedDays(now: now, settings: s), 0)
        let e = EarningsCalculator.calculate(now: now, settings: s, work: w)
        XCTAssertNil(e.earned); XCTAssertTrue(e.reason!.contains("为 0"))
    }
    func testUnsetAndZeroAndCustomDaily() {
        var s = settings(); let now = date("2026-10-12 15:00:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        s.monthlySalary = nil; XCTAssertNil(EarningsCalculator.calculate(now: now, settings: s, work: w).earned)
        s.monthlySalary = 0; XCTAssertEqual(EarningsCalculator.calculate(now: now, settings: s, work: w).earned, 0)
        s.payMode = .customDaily; s.customDaily = 200; s.monthlySalary = nil
        XCTAssertEqual(EarningsCalculator.calculate(now: now, settings: s, work: w).earned, 125)
    }
    func testMoneyParsingAndRounding() throws {
        XCTAssertNil(try Money.parse("  ")); XCTAssertEqual(try Money.parse("0"), 0)
        XCTAssertEqual(try Money.parse("21,750.00"), 21750)
        XCTAssertEqual(try Money.parse("10000000.00"), 10000000)
        for input in ["-1", "NaN", "inf", "∞", "10000000.01", "1.234", "1,23", "1e3", "abc", ".5"] { XCTAssertThrowsError(try Money.parse(input), input) }
        XCTAssertEqual(Money.formatted(Decimal(string: "1.005")!), "¥1.01")
        XCTAssertEqual(Money.formatted(0), "¥0.00"); XCTAssertEqual(Money.formatted(21750), "¥21,750.00")
        XCTAssertFalse(Money.valid(.nan))
    }
    func testNoEarlyDailyRounding() {
        var s = settings(); s.monthlySalary = 100; s.fixedDays = 3
        let now = date("2026-10-12 15:00:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        let e = EarningsCalculator.calculate(now: now, settings: s, work: w)
        XCTAssertEqual(Money.formatted(e.earned!), "¥20.83")
        XCTAssertNotEqual(e.earned, Decimal(string: "33.33")! * Decimal(string: "0.625")!)
    }
    func testImmediateRecalculationAndPrivacy() {
        var s = settings(); let now = date("2026-10-12 15:00:00")
        var w = ScheduleCalculator.snapshot(now: now, settings: s); var e = EarningsCalculator.calculate(now: now, settings: s, work: w)
        XCTAssertEqual(e.earned, 625); s.monthlySalary = 43500
        e = EarningsCalculator.calculate(now: now, settings: s, work: w); XCTAssertEqual(e.earned, 1250)
        s.endMinute = 19 * 60; w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(w.progress, 5.0 / 9.0)
        s.menuMode = .earnings; s.hideEarnings = true
        XCTAssertEqual(DisplayFormatter.menu(settings: s, work: w, earnings: e), "今日 ¥••••")
        XCTAssertEqual(e.earned, 1250)
    }
    func testCountdownRoundingAndStates() {
        XCTAssertEqual(ScheduleCalculator.countdown(1), "<1分钟"); XCTAssertEqual(ScheduleCalculator.countdown(59.9), "<1分钟")
        XCTAssertEqual(ScheduleCalculator.countdown(60), "00:01"); XCTAssertEqual(ScheduleCalculator.countdown(60.1), "00:02")
        XCTAssertEqual(ScheduleCalculator.countdown(1, secondsIncluded: true), "00:00:01")
        let s = settings(); let now = date("2026-10-12 08:59:00"); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(DisplayFormatter.menu(settings: s, work: w, earnings: EarningsCalculator.calculate(now: now, settings: s, work: w)), "未上班")
    }
    func testValidation() {
        var s = settings(); XCTAssertNoThrow(try s.validated())
        s.weekdays = []; XCTAssertThrowsError(try s.validated()); s = settings()
        s.endMinute = s.startMinute; XCTAssertThrowsError(try s.validated()); s = settings()
        s.startMinute = 20 * 60; XCTAssertThrowsError(try s.validated()); s = settings()
        s.lunchStart = s.startMinute; XCTAssertThrowsError(try s.validated()); s = settings()
        s.fixedDays = 0; XCTAssertThrowsError(try s.validated()); s = settings()
        s.monthlySalary = .nan; XCTAssertThrowsError(try s.validated()); s = settings()
        s.timeZoneID = "invalid"; XCTAssertThrowsError(try s.validated()); s = settings()
        s.overrides["2026-02-30"] = true; XCTAssertThrowsError(try s.validated())
    }
    func testMigrationAndCorruptionRecoveryDetection() throws {
        let data = try JSONEncoder().encode(settings())
        XCTAssertEqual(try SettingsCodec.decode(data), settings())
        XCTAssertEqual(try SettingsCodec.decode(Data("{}".utf8)).schemaVersion, 1)
        XCTAssertThrowsError(try SettingsCodec.decode(Data("garbage".utf8)))
        XCTAssertThrowsError(try SettingsCodec.decode(Data(#"{"schemaVersion":99}"#.utf8)))
        XCTAssertThrowsError(try SettingsCodec.decode(Data(#"{"monthlySalary":"bad"}"#.utf8)))
    }
    func testWorkingTimezoneNotSystemTimezone() {
        var s = settings(); s.timeZoneID = "America/New_York"
        let now = date("2026-10-12 15:00:00") // New York is 03:00 at this instant.
        XCTAssertEqual(ScheduleCalculator.snapshot(now: now, settings: s).state, .before)
        XCTAssertEqual(s.calendar.component(.hour, from: now), 3)
    }
    func testDSTGapAndRepeatedTimePolicy() {
        var s = settings(); s.timeZoneID = "America/New_York"; s.weekdays = Set(1...7); s.lunchEnabled = false
        let spring = date("2026-03-08 12:00:00", zone: s.timeZoneID)
        let gap = ScheduleCalculator.localTime(150, on: spring, calendar: s.calendar)
        XCTAssertEqual(s.calendar.component(.hour, from: gap), 3); XCTAssertEqual(s.calendar.component(.minute, from: gap), 0)
        s.startMinute = 90; s.endMinute = 270
        XCTAssertEqual(ScheduleCalculator.snapshot(now: spring, settings: s).totalSeconds, 7200)
        let autumn = date("2026-11-01 12:00:00", zone: s.timeZoneID)
        let fold = ScheduleCalculator.localTime(90, on: autumn, calendar: s.calendar)
        XCTAssertEqual(s.calendar.timeZone.secondsFromGMT(for: fold), -4 * 3600)
        s.endMinute = 150
        XCTAssertEqual(ScheduleCalculator.snapshot(now: autumn, settings: s).totalSeconds, 7200)
    }
    func testDSTCollapsedIntervalsAreHandled() {
        var s = settings(); s.timeZoneID = "America/New_York"; s.weekdays = Set(1...7); s.lunchEnabled = false; s.startMinute = 130; s.endMinute = 170
        let now = date("2026-03-08 12:00:00", zone: s.timeZoneID); let w = ScheduleCalculator.snapshot(now: now, settings: s)
        XCTAssertEqual(w.totalSeconds, 0); XCTAssertNil(EarningsCalculator.calculate(now: now, settings: s, work: w).earned)
    }
}
