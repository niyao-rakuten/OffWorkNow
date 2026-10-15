import XCTest
@testable import WorkdayCore

final class DailyReportTests: ChineseLocalizationTestCase {
    #if DEBUG
    func testDebugClearOnlyRemovesRequestedDateAndZone() throws {
        var archive = DailyReportArchive()
        let original = report()
        try archive.upsert(original)
        var otherZone = original; otherZone.timeZoneID = "Asia/Tokyo"
        try archive.upsert(otherZone)
        let next = DailyReport.snapshot(now: helper.date("2026-10-13 18:00:00"), settings: helper.settings(),
            checkout: nil, hydration: HydrationSummary(cups: 0, totalML: 0))
        try archive.upsert(next)
        archive.debugRemove(dateKey: original.dateKey, timeZoneID: original.timeZoneID)
        XCTAssertEqual(Set(archive.records.map(\.id)), Set([otherZone.id, next.id]))
        XCTAssertEqual(try DailyReportArchive.decode(JSONEncoder().encode(archive)).records.count, 2)
    }
    #endif
    let helper = CalculationTests()
    func report(_ time: String = "18:00:00", water: Int = 1500) -> DailyReport {
        DailyReport.snapshot(now: helper.date("2026-10-12 " + time), settings: helper.settings(), checkout: nil, hydration: HydrationSummary(cups: 3, totalML: water))
    }
    func testWaterAndSalaryCopy() {
        XCTAssertEqual(report(water: 1499).waterMessage, "今天喝水有点少哦，要多喝水才能促进代谢哦～")
        XCTAssertEqual(report().waterMessage, "今天喝了1500ml水，乖乖喝水的宝宝最棒了！")
        XCTAssertEqual(report().salaryMessage, "辛苦啦～今天收入1,000.00元，底薪到手，快乐下班～")
    }
    func testAssistantSummaryWaterAndOvertimeThresholds() {
        XCTAssertTrue(report(water: 1499).assistantSummary(hideEarnings: false).contains("今天喝水有点少哦，要多喝水才能促进代谢，身体才能棒棒～"))
        XCTAssertTrue(report(water: 1500).assistantSummary(hideEarnings: false).contains("今天喝了1500ml水，乖乖喝水的宝宝最棒了！"))
        XCTAssertTrue(report(water: 2000).assistantSummary(hideEarnings: false).contains("今天喝了2000ml水"))
        XCTAssertTrue(report("18:14:59").assistantSummary(hideEarnings: false).contains("今天没有加班，宝贝真棒～ 快点回去休息吧"))
        XCTAssertTrue(report("18:15:00").assistantSummary(hideEarnings: false).contains("快点回家，不要让底薪被稀释"))
        XCTAssertFalse(report("18:29:59").assistantSummary(hideEarnings: false).contains("天呐噜"))
        XCTAssertTrue(report("18:30:00").assistantSummary(hideEarnings: false).contains("今天竟然加班 0 h,30 min"))
        XCTAssertTrue(report("19:31:00").assistantSummary(hideEarnings: false).contains("今天竟然加班 1 h,31 min"))
        XCTAssertTrue(report().assistantSummary(hideEarnings: false).contains("今天收入1,000.00元，底薪到手，快乐下班～"))
        XCTAssertFalse(report().assistantSummary(hideEarnings: true).contains("收入"))
        var unset = report(); unset.earned = nil
        XCTAssertFalse(unset.assistantSummary(hideEarnings: false).contains("收入"))
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
    func testAssistantReportUsesCheckoutSnapshotAndRespectsHiddenIncome() {
        let settings = helper.settings()
        let checkout = CheckoutRecord(now: helper.date("2026-10-12 18:20:00"), settings: settings)
        let report = DailyReport.snapshot(now: helper.date("2026-10-12 20:00:00"), settings: settings,
            checkout: checkout, hydration: HydrationSummary(cups: 3, totalML: 1500))
        let prompt = report.assistantReport(hideEarnings: false)
        XCTAssertTrue(prompt.contains("实际打卡：18:20:00"))
        XCTAssertTrue(prompt.contains("1500 ml，共 3 杯"))
        XCTAssertTrue(prompt.contains("加班：0h20min"))
        XCTAssertTrue(prompt.contains(Money.formatted(1000)))
        let hidden = report.assistantReport(hideEarnings: true)
        XCTAssertFalse(hidden.contains(Money.formatted(1000)))
        XCTAssertTrue(hidden.contains("已隐藏"))
        XCTAssertTrue(prompt.contains("日期：2026-10-12\n时区："))
        XCTAssertTrue(prompt.contains("计划下班：18:00:00\n实际打卡：18:20:00\n饮水："))
        XCTAssertTrue(prompt.contains("今天喝了1500ml水，乖乖喝水的宝宝最棒了！"))
        XCTAssertTrue(prompt.contains("快点回家，不要让底薪被稀释"))
        XCTAssertFalse(prompt.contains("内部事件"))
        let message = AssistantMessage(role: .assistant, content: prompt, proactive: true)
        XCTAssertTrue(message.complete)
        XCTAssertEqual(message.role, .assistant)
        XCTAssertNil(message.usage)
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
