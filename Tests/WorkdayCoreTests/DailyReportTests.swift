import XCTest
@testable import WorkdayCore

final class DailyReportTests: XCTestCase {
    let helper = CalculationTests()
    func report(_ time: String = "18:00:00", water: Int = 1500) -> DailyReport {
        DailyReport.snapshot(now: helper.date("2026-10-12 " + time), settings: helper.settings(), checkout: nil, hydration: HydrationSummary(cups: 3, totalML: water))
    }
    func testWaterAndSalaryCopy() {
        XCTAssertEqual(report(water: 1499).waterMessage, "今天喝水有点少哦，要多喝水才能促进代谢哦～")
        XCTAssertEqual(report().waterMessage, "今天喝了1500ml水，乖乖喝水的宝宝最棒了！")
        XCTAssertEqual(report().salaryMessage, "辛苦啦～今天收入1,000.00元，底薪到手，快乐下班～")
    }
    func testOvertimeBoundaries() {
        XCTAssertEqual(report("18:14:59").mood, .happy)
        XCTAssertEqual(report("18:15:00").mood, .neutral)
        XCTAssertEqual(report("18:29:59").mood, .neutral)
        XCTAssertEqual(report("18:30:00").mood, .crying)
        XCTAssertTrue(report("19:31:00").overtimeMessage.contains("1 h,31 min"))
        XCTAssertEqual(report("18:15:00").overtimeMessage, "辛苦了，快点回家，不要让底薪被稀释")
        XCTAssertEqual(report().overtimeMessage, "今天没有加班，宝贝真棒～ 快点回去休息吧")
        XCTAssertNil(report("17:59:59").mood)
    }
    func testCheckoutFreezesPayAndOvertime() {
        let s = helper.settings()
        let early = CheckoutRecord(now: helper.date("2026-10-12 15:00:00"), settings: s)
        let saved = DailyReport.snapshot(now: helper.date("2026-10-12 20:00:00"), settings: s, checkout: early, hydration: HydrationSummary(cups: 4, totalML: 2000))
        XCTAssertEqual(saved.earned, 625); XCTAssertEqual(saved.overtimeSeconds, 0); XCTAssertEqual(saved.mood, .happy)
        let late = CheckoutRecord(now: helper.date("2026-10-12 18:20:00"), settings: s)
        let lateReport = DailyReport.snapshot(now: helper.date("2026-10-12 20:00:00"), settings: s, checkout: late, hydration: HydrationSummary(cups: 0, totalML: 0))
        XCTAssertEqual(lateReport.overtimeSeconds, 1200); XCTAssertEqual(lateReport.earned, 1000)
    }
    func testArchiveRoundTripRolloverAndHistory() throws {
        var archive = DailyReportArchive(); try archive.upsert(report()); try archive.upsert(report("19:00:00", water: 2000))
        XCTAssertEqual(archive.records.count, 1)
        let historical = archive.records[0]
        var s = helper.settings(); s.monthlySalary = 43500
        let next = DailyReport.snapshot(now: helper.date("2026-10-13 18:00:00"), settings: s, checkout: nil, hydration: HydrationSummary(cups: 1, totalML: 500))
        try archive.upsert(next)
        let restored = try DailyReportArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(restored.records.count, 2); XCTAssertEqual(restored.records[0], historical)
        XCTAssertEqual(restored.records[1].earned, 2000)
        try archive.upsert(report("18:00:00", water: 0))
        XCTAssertEqual(archive.records[0], historical, "Clock rollback must not erase a newer snapshot")
    }
    func testRestDayAndInvalidArchive() throws {
        let rest = DailyReport.snapshot(now: helper.date("2026-10-17 19:00:00"), settings: helper.settings(), checkout: nil, hydration: HydrationSummary(cups: 2, totalML: 1000))
        XCTAssertNil(rest.mood); XCTAssertEqual(rest.overtimeSeconds, 0)
        var archive = DailyReportArchive(); try archive.upsert(rest); archive.schemaVersion = 99
        XCTAssertThrowsError(try DailyReportArchive.decode(JSONEncoder().encode(archive)))
        var invalid = rest; invalid.waterML = -1; XCTAssertThrowsError(try invalid.validated())
        invalid = rest; invalid.overtimeSeconds = .infinity; XCTAssertThrowsError(try invalid.validated())
    }
}
