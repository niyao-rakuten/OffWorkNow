import XCTest
@testable import WorkdayCore

final class ReminderTests: ChineseLocalizationTestCase {
    let helper = CalculationTests()
    func testStartupHourlyBoundaries() {
        let s = helper.settings(); let ledger = ReminderLedger()
        for hour in [9,10,11,13,14,15,16,17] {
            let now = helper.date(String(format: "2026-10-12 %02d:00:05", hour))
            XCTAssertNotNil(ReminderPlanner.startupEvent(now: now, settings: s, ledger: ledger, pause: nil))
        }
        for time in ["08:00:00", "12:00:00", "18:00:00", "10:00:11", "10:05:00"] {
            XCTAssertNil(ReminderPlanner.startupEvent(now: helper.date("2026-10-12 " + time), settings: s, ledger: ledger, pause: nil), time)
        }
        XCTAssertNotNil(ReminderPlanner.startupEvent(now: helper.date("2026-10-12 10:00:10"), settings: s, ledger: ledger, pause: nil))
    }
    func testNextSkipsLunchAndOffworkIsSeparate() {
        let s = helper.settings(); let ledger = ReminderLedger()
        let lunch = ReminderPlanner.next(now: helper.date("2026-10-12 11:59:59"), settings: s, ledger: ledger, pause: nil)!
        XCTAssertEqual(lunch.date, helper.date("2026-10-12 13:00:00")); XCTAssertEqual(lunch.kind, .hourly)
        let end = ReminderPlanner.next(now: helper.date("2026-10-12 17:00:01"), settings: s, ledger: ledger, pause: nil)!
        XCTAssertEqual(end.date, helper.date("2026-10-12 18:00:00")); XCTAssertEqual(end.kind, .offwork)
        let tomorrow = ReminderPlanner.next(now: helper.date("2026-10-12 18:00:00"), settings: s, ledger: ledger, pause: nil)!
        XCTAssertEqual(tomorrow.date, helper.date("2026-10-13 09:00:00"))
    }
    func testPauseExpiresByAbsoluteDateAndAcrossDays() {
        let s = helper.settings(); let now = helper.date("2026-10-12 09:30:00")
        let pause = ReminderPause(until: now.addingTimeInterval(3600), dateKey: "2026-10-12")
        XCTAssertTrue(pause.active(now: now, settings: s)); XCTAssertFalse(pause.active(now: now.addingTimeInterval(3600), settings: s))
        XCTAssertEqual(ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: pause)?.date, helper.date("2026-10-12 11:00:00"))
        let long = ReminderPause(until: helper.date("2026-10-14 12:00:00"), dateKey: "2026-10-12")
        XCTAssertFalse(long.active(now: helper.date("2026-10-13 09:00:00"), settings: s))
    }
    func testPauseDoesNotDisableOffworkOrRestoreMasterSwitch() {
        var s = helper.settings(); let now = helper.date("2026-10-12 15:00:01")
        let pause = ReminderPause(until: helper.date("2026-10-12 19:00:00"), dateKey: "2026-10-12")
        XCTAssertEqual(ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: pause)?.kind, .offwork)
        s.hourlyEnabled = false
        XCTAssertNil(ReminderPlanner.startupEvent(now: helper.date("2026-10-12 16:00:00"), settings: s, ledger: ReminderLedger(), pause: nil))
    }
    func testRestartAndClockRollbackDoNotRepeat() throws {
        let s = helper.settings(); let now = helper.date("2026-10-12 10:00:00")
        let event = ReminderPlanner.startupEvent(now: now, settings: s, ledger: ReminderLedger(), pause: nil)!
        XCTAssertEqual(event.id, "hourly.Asia/Shanghai.2026-10-12.10")
        var ledger = ReminderLedger(); ledger.consume(event, record: EventRecord(notification: "submitted", speech: "played"))
        let restored = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertNil(ReminderPlanner.startupEvent(now: now, settings: s, ledger: restored, pause: nil))
        XCTAssertEqual(ReminderPlanner.next(now: now.addingTimeInterval(-1800), settings: s, ledger: restored, pause: nil)?.date, helper.date("2026-10-12 11:00:00"))
        XCTAssertFalse(ReminderPlanner.due(event, now: now, settings: s, ledger: restored, pause: nil))
    }
    func testClockJumpWakeNeverCatchUp() {
        let s = helper.settings(); let now = helper.date("2026-10-12 09:01:00")
        let event = ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: nil)!
        XCTAssertFalse(ReminderPlanner.due(event, now: event.date.addingTimeInterval(-30), settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertFalse(ReminderPlanner.due(event, now: event.date.addingTimeInterval(11), settings: s, ledger: ReminderLedger(), pause: nil))
        let wake = helper.date("2026-10-12 15:15:00")
        XCTAssertFalse(ReminderPlanner.due(event, now: wake, settings: s, ledger: ReminderLedger(), pause: nil))
        XCTAssertEqual(ReminderPlanner.next(now: wake, settings: s, ledger: ReminderLedger(), pause: nil)?.date, helper.date("2026-10-12 16:00:00"))
    }
    func testOffworkStartupAndSettingsChangeDoNotCatchUp() {
        var s = helper.settings(); let now = helper.date("2026-10-12 18:00:05")
        XCTAssertNil(ReminderPlanner.startupEvent(now: now, settings: s, ledger: ReminderLedger(), pause: nil))
        s.endMinute = 16 * 60
        XCTAssertGreaterThan(ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: nil)!.date, now)
        let e = ReminderPlanner.event(date: helper.date("2026-10-12 16:00:00"), kind: .offwork, settings: s)
        var ledger = ReminderLedger(); ledger.consume(e); s.endMinute = 19 * 60
        XCTAssertFalse(ReminderPlanner.allowed(e, settings: s, pause: nil))
        XCTAssertNotEqual(ReminderPlanner.next(now: now, settings: s, ledger: ledger, pause: nil)?.kind, .offwork)
    }
    func testRandomUsesEnabledCategoriesAndAvoidsConsecutiveRepeat() {
        for category in ReminderCategory.allCases {
            XCTAssertGreaterThanOrEqual(HealthMessages.messages[category]!.count, 6)
            var previous: String?
            for _ in 0..<200 {
                let message = HealthMessages.choose(categories: [category], previous: previous)
                XCTAssertTrue(HealthMessages.messages[category]!.contains(message)); XCTAssertNotEqual(message, previous); previous = message
            }
        }
        XCTAssertEqual(HealthMessages.choose(categories: [], previous: nil), "工作辛苦了，记得适当休息")
        // First choice is the category, second is a sentence: categories have equal selection weight.
        for (index, category) in ReminderCategory.allCases.enumerated() {
            var calls = 0
            let message = HealthMessages.choose(categories: Set(ReminderCategory.allCases), previous: nil, pick: { limit in calls += 1; return calls == 1 ? index : 0 })
            XCTAssertEqual(message, HealthMessages.messages[category]!.first)
        }
    }
    func testTimezoneAndDateOverrideAffectEvents() {
        var s = helper.settings(); s.overrides["2026-10-12"] = false
        XCTAssertNil(ReminderPlanner.startupEvent(now: helper.date("2026-10-12 10:00:00"), settings: s, ledger: ReminderLedger(), pause: nil))
        s.timeZoneID = "America/New_York"
        let now = helper.date("2026-10-13 10:00:00", zone: s.timeZoneID)
        XCTAssertEqual(ReminderPlanner.startupEvent(now: now, settings: s, ledger: ReminderLedger(), pause: nil)?.id, "hourly.America/New_York.2026-10-13.10")
    }
    func testHalfHourDSTTransitionStillUsesNaturalHours() {
        var s = helper.settings(); s.timeZoneID = "Australia/Lord_Howe"; s.weekdays = Set(1...7)
        s.lunchEnabled = false; s.startMinute = 60; s.endMinute = 5 * 60
        let now = helper.date("2026-10-04 01:00:01", zone: s.timeZoneID)
        let next = ReminderPlanner.next(now: now, settings: s, ledger: ReminderLedger(), pause: nil)!
        XCTAssertEqual(s.calendar.component(.hour, from: next.date), 3)
        XCTAssertEqual(s.calendar.component(.minute, from: next.date), 0)
        XCTAssertNil(ReminderPlanner.startupEvent(now: helper.date("2026-10-04 02:30:01", zone: s.timeZoneID), settings: s, ledger: ReminderLedger(), pause: nil))
    }

}
