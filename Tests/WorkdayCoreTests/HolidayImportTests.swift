import XCTest
@testable import WorkdayCore

final class HolidayImportTests: ChineseLocalizationTestCase {
    static let notices: [Int: String] = [
        2026: """
        一、元旦：1月1日（周四）至3日（周六）放假调休，共3天。1月4日（周日）上班。
        二、春节：2月15日（农历腊月二十八、周日）至23日（农历正月初七、周一）放假调休，共9天。2月14日（周六）、2月28日（周六）上班。
        三、清明节：4月4日（周六）至6日（周一）放假，共3天。
        四、劳动节：5月1日（周五）至5日（周二）放假调休，共5天。5月9日（周六）上班。
        五、端午节：6月19日（周五）至21日（周日）放假，共3天。
        六、中秋节：9月25日（周五）至27日（周日）放假，共3天。
        七、国庆节：10月1日（周四）至7日（周三）放假调休，共7天。9月20日（周日）、10月10日（周六）上班。
        """,
        2025: """
        一、元旦：1月1日（周三）放假1天，不调休。
        二、春节：1月28日（农历除夕、周二）至2月4日（农历正月初七、周二）放假调休，共8天。1月26日（周日）、2月8日（周六）上班。
        三、清明节：4月4日（周五）至6日（周日）放假，共3天。
        四、劳动节：5月1日（周四）至5日（周一）放假调休，共5天。4月27日（周日）上班。
        五、端午节：5月31日（周六）至6月2日（周一）放假，共3天。
        六、国庆节、中秋节：10月1日（周三）至8日（周三）放假调休，共8天。9月28日（周日）、10月11日（周六）上班。
        """,
        2024: """
        一、元旦：1月1日放假，与周末连休。
        二、春节：2月10日至17日放假调休，共8天。2月4日（星期日）、2月18日（星期日）上班。鼓励各单位结合带薪年休假等制度落实，安排职工在除夕（2月9日）休息。
        三、清明节：4月4日至6日放假调休，共3天。4月7日（星期日）上班。
        四、劳动节：5月1日至5日放假调休，共5天。4月28日（星期日）、5月11日（星期六）上班。
        五、端午节：6月10日放假，与周末连休。
        六、中秋节：9月15日至17日放假调休，共3天。9月14日（星期六）上班。
        七、国庆节：10月1日至7日放假调休，共7天。9月29日（星期日）、10月12日（星期六）上班。
        """,
        2023: """
        一、元旦：2022年12月31日至2023年1月2日放假调休，共3天。
        二、春节：1月21日至27日放假调休，共7天。1月28日（星期六）、1月29日（星期日）上班。
        三、清明节：4月5日放假，共1天。
        四、劳动节：4月29日至5月3日放假调休，共5天。4月23日（星期日）、5月6日（星期六）上班。
        五、端午节：6月22日至24日放假调休，共3天。6月25日（星期日）上班。
        六、中秋节、国庆节：9月29日至10月6日放假调休，共8天。10月7日（星期六）、10月8日（星期日）上班。
        """,
        2022: """
        **一、元旦**：2022年1月1日至3日放假，共3天。
        二、春节：1月31日至2月6日放假调休，共7天。1月29日（星期六）、1月30日（星期日）上班。
        三、清明节：4月3日至5日放假调休，共3天。4月2日（星期六）上班。
        四、劳动节：4月30日至5月4日放假调休，共5天。4月24日（星期日）、5月7日（星期六）上班。
        五、端午节：6月3日至5日放假，共3天。
        六、中秋节：9月10日至12日放假，共3天。
        七、国庆节：10月1日至7日放假调休，共7天。10月8日（星期六）、10月9日（星期日）上班。
        """
    ]
    func testAllFiveProvidedNotices() throws {
        for (year, rest, work, groups) in [(2026, 33, 6, 7), (2025, 28, 5, 6), (2024, 28, 8, 7), (2023, 27, 7, 6), (2022, 31, 7, 7)] {
            let parsed = try HolidayNoticeParser.parse(Self.notices[year]!, year: year)
            XCTAssertEqual(parsed.restCount, rest, "\(year)")
            XCTAssertEqual(parsed.workCount, work, "\(year)")
            XCTAssertEqual(parsed.holidays.count, groups, "\(year)")
            var settings = CalculationTests().settings()
            settings.overrides = parsed.overrides
            _ = try settings.validated()
        }
    }
    func testCrossYearAndCrossMonthAreInclusive() throws {
        let parsed = try HolidayNoticeParser.parse(Self.notices[2023]!, year: 2023)
        XCTAssertEqual(parsed.holidays[0].holidays, ["2022-12-31", "2023-01-01", "2023-01-02"])
        XCTAssertEqual(parsed.holidays[3].holidays, ["2023-04-29", "2023-04-30", "2023-05-01", "2023-05-02", "2023-05-03"])
        XCTAssertEqual(parsed.overrides["2023-05-06"], true)
    }
    func testLunarDescriptionsAndOptionalLeaveAreNotImported() throws {
        let parsed = try HolidayNoticeParser.parse(Self.notices[2024]!, year: 2024)
        XCTAssertNil(parsed.overrides["2024-02-09"])
        XCTAssertEqual(parsed.overrides["2024-02-10"], false)
        XCTAssertEqual(parsed.overrides["2024-02-18"], true)
        let lunar = try HolidayNoticeParser.parse(Self.notices[2026]!, year: 2026)
        XCTAssertEqual(lunar.holidays[1].holidays.first, "2026-02-15")
        XCTAssertEqual(lunar.holidays[1].holidays.last, "2026-02-23")
    }
    func testWhitespaceASCIIParenthesesAndAbbreviatedWorkdays() throws {
        let parsed = try HolidayNoticeParser.parse("一、 春节: 2 月 10 日 (星期六) 至 17 日放假。2月4日、18日上班。", year: 2024)
        XCTAssertEqual(parsed.restCount, 8)
        XCTAssertEqual(parsed.overrides["2024-02-04"], true)
        XCTAssertEqual(parsed.overrides["2024-02-18"], true)
        let implicitYear = try HolidayNoticeParser.parse("元旦：12月31日至1月2日放假。", year: 2022)
        XCTAssertEqual(implicitYear.holidays[0].holidays, ["2022-12-31", "2023-01-01", "2023-01-02"])
    }
    func testMalformedDatesAndConflictingInstructionsRejectEntireImport() {
        for text in ["", "没有日期", "一、春节：2月30日放假。", "一、春节：2月18日至10日放假。", "一、元旦：1月1日放假。1月1日上班。", "一、元旦：1月1日放假。二、春节：无法识别。", "一、元旦：1月1日放假。2月8日、错误上班。", "一、元旦：1月1日放假。2月X日放假。", "2025年：一、元旦：1月1日放假。"] {
            XCTAssertThrowsError(try HolidayNoticeParser.parse(text, year: 2026), text)
        }
        XCTAssertThrowsError(try HolidayNoticeParser.parse(Self.notices[2026]!, year: 26))
        XCTAssertThrowsError(try HolidayNoticeParser.parse(String(repeating: "一", count: 100_001), year: 2026))
    }
    func testMergingPreservesUnrelatedOverridesAndChangesWorkCalculations() throws {
        let parsed = try HolidayNoticeParser.parse(Self.notices[2026]!, year: 2026)
        var settings = CalculationTests().settings()
        settings.overrides = ["2026-11-11": false, "2026-01-01": true]
        settings.overrides.merge(parsed.overrides) { _, new in new }
        XCTAssertEqual(settings.overrides["2026-11-11"], false)
        XCTAssertEqual(settings.overrides["2026-01-01"], false)
        XCTAssertFalse(ScheduleCalculator.isWorkday(CalculationTests().date("2026-01-01 12:00:00"), settings: settings))
        XCTAssertTrue(ScheduleCalculator.isWorkday(CalculationTests().date("2026-01-04 12:00:00"), settings: settings))
    }
}
