import XCTest
@testable import WorkdayCore

final class HydrationTests: XCTestCase {
    let helper = CalculationTests()
    func testEachClickCreatesOneCupAndKeepsConfiguredVolume() throws {
        var s = helper.settings(); s.cupVolumeML = 500
        let now = helper.date("2026-10-12 10:00:00")
        var log = HydrationLog(now: now, settings: s)
        try log.add(now: now, settings: s); try log.add(now: now, settings: s)
        XCTAssertEqual(log.summary(now: now, settings: s), HydrationSummary(cups: 2, totalML: 1000))
        XCTAssertNotEqual(log.entries[0].id, log.entries[1].id)
        s.cupVolumeML = 250; try log.add(now: now.addingTimeInterval(60), settings: s)
        XCTAssertEqual(log.entries.map(\.volumeML), [500,500,250])
        XCTAssertEqual(log.summary(now: now.addingTimeInterval(60), settings: s).totalML, 1250)
    }
    func testPersistenceAndUndoOneCup() throws {
        let s = helper.settings(), now = helper.date("2026-10-12 10:00:00")
        var log = HydrationLog(now: now, settings: s); try log.add(now: now, settings: s); try log.add(now: now, settings: s)
        var saved = try JSONDecoder().decode(HydrationLog.self, from: JSONEncoder().encode(log)).validated()
        XCTAssertEqual(saved, log); saved.undoLast(now: now, settings: s)
        XCTAssertEqual(saved.summary(now: now, settings: s).cups, 1)
        saved.undoLast(now: now, settings: s); saved.undoLast(now: now, settings: s)
        XCTAssertEqual(saved.summary(now: now, settings: s).totalML, 0)
    }
    func testCrossDayResetAndRestDayStillCanDrink() throws {
        let s = helper.settings(), now = helper.date("2026-10-16 23:59:00")
        var log = HydrationLog(now: now, settings: s); try log.add(now: now, settings: s)
        let next = helper.date("2026-10-17 00:00:00")
        XCTAssertEqual(log.summary(now: next, settings: s).cups, 0)
        try log.add(now: next, settings: s)
        XCTAssertEqual(log.dateKey, "2026-10-17"); XCTAssertEqual(log.summary(now: next, settings: s).cups, 1)
    }
    func testTimezoneAndClockRollback() throws {
        var s = helper.settings(); let now = helper.date("2026-10-12 10:00:00")
        var log = HydrationLog(now: now, settings: s); try log.add(now: now.addingTimeInterval(60), settings: s)
        XCTAssertEqual(log.summary(now: now, settings: s).cups, 0)
        XCTAssertEqual(log.summary(now: now.addingTimeInterval(60), settings: s).cups, 1)
        s.timeZoneID = "America/New_York"
        XCTAssertEqual(log.summary(now: now.addingTimeInterval(60), settings: s).cups, 0)
    }
    func testCupVolumeValidationAndDefaultsMigration() throws {
        XCTAssertEqual(try HydrationCalculator.parseCupVolume(" 500 "), 500)
        for value in ["", "0", "-5", "500.5", "NaN", "2,000", "2001", "9999999999999999999999999"] { XCTAssertThrowsError(try HydrationCalculator.parseCupVolume(value), value) }
        var s = helper.settings(); s.cupVolumeML = 0; XCTAssertThrowsError(try s.validated())
        XCTAssertEqual(try SettingsCodec.decode(Data("{}".utf8)).cupVolumeML, 500)
        XCTAssertEqual(PetKind.goldfish.title, "小金鱼")
        XCTAssertTrue(PetKind.allCases.contains(.goldfish))
    }
    func testHydrationCorruptionIsRejected() throws {
        let s = helper.settings(), now = helper.date("2026-10-12 10:00:00")
        var log = HydrationLog(now: now, settings: s); try log.add(now: now, settings: s)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as! [String: Any]
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(HydrationLog.self, from: JSONSerialization.data(withJSONObject: object)).validated())
    }
}
