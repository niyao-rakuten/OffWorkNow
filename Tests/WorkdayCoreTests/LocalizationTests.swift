import XCTest
@testable import WorkdayCore

/// Existing copy expectations explicitly exercise Chinese, independent of the test host.
class ChineseLocalizationTestCase: XCTestCase {
    private var previousLanguage: Any?
    override func setUp() {
        super.setUp()
        previousLanguage = UserDefaults.standard.object(forKey: L10n.preferenceKey)
        UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: L10n.preferenceKey)
    }
    override func tearDown() {
        if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: L10n.preferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) }
        super.tearDown()
    }
}

final class LocalizationTests: ChineseLocalizationTestCase {
    func testProactiveHistorySwitchesLanguageAndPreservesUserText() throws {
        var pet = AssistantMessage(role: .assistant, content: "中文提醒", proactive: true)
        pet.localizedContents = ["zh-Hans": "中文提醒", "en": "Water reminder"]
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(decoded.displayedContent, "中文提醒")
        let user = AssistantMessage(role: .user, content: "用户原文")
        UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
        XCTAssertEqual(decoded.displayedContent, "Water reminder")
        XCTAssertEqual(user.displayedContent, "用户原文")
        XCTAssertEqual(pet.content, "中文提醒")
    }
    func testReminderCatalogCanRenderTheSameChosenMessageInEitherLanguage() {
        for message in HealthMessages.messages.values.flatMap({ $0 }) {
            let key = L10n.sourceKey(for: message)
            let english = L10n.text(key, language: .english)
            XCTAssertNil(english.range(of: "\\p{Han}", options: .regularExpression))
            XCTAssertEqual(L10n.sourceKey(for: english), key)
            XCTAssertEqual(L10n.text(key, language: .simplifiedChinese), message)
        }
        for seconds in [300.0, 600.0] {
            XCTAssertNil(OvertimeCalculator.message(seconds: seconds, language: .english).range(of: "\\p{Han}", options: .regularExpression))
        }
    }
    func testExplicitLanguagesAndFallback() {
        XCTAssertEqual(L10n.text("打卡下班", language: .english), "Clock Out")
        XCTAssertEqual(L10n.text("打卡下班", language: .simplifiedChinese), "打卡下班")
        XCTAssertEqual(L10n.text("unknown.key", language: .english), "unknown.key")
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-TW", "en"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]), .english)
    }
    func testInterpolationPreservesArguments() {
        XCTAssertEqual(L10n.format("今天{0}杯，共{1}毫升", "3", "1500", language: .english), "3 cups today, 1500 milliliters total")
        XCTAssertEqual(L10n.format("今天{0}杯，共{1}毫升", "{1}", "1500", language: .english), "{1} cups today, 1500 milliliters total")
    }
    func testSwitchingUpdatesCoreCopyWithoutChangingScheduleOrHistory() throws {
        var settings = WorkSettings(); settings.timeZoneID = "Asia/Shanghai"
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(WorkState.working.title, "工作中")
        XCTAssertEqual(HealthMessages.messages[.walk]?.first, "站起来走两分钟，活动一下肩背。")
        UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.selection, .english)
        XCTAssertEqual(WorkState.working.title, "Working")
        XCTAssertEqual(HealthMessages.messages[.walk]?.first, "Stand up and walk for two minutes. Relax your shoulders and back.")
        XCTAssertEqual(PetKind.bunGirl.title, "Bun-Haired Girl")
        XCTAssertEqual(try SettingsCodec.decode(data), settings)
        settings.monthlySalary = 1000; settings.menuMode = .earnings
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-10-13T10:00:00Z")!
        let work = ScheduleCalculator.snapshot(now: now, settings: settings)
        let unavailable = EarningsSnapshot(daily: nil, earned: nil, reason: L10n.text("当月计划工作日为 0，请修改工作安排"))
        XCTAssertEqual(DisplayFormatter.menu(settings: settings, work: work, earnings: unavailable), "Cannot estimate earnings")
        UserDefaults.standard.set("invalid", forKey: L10n.preferenceKey)
        XCTAssertEqual(L10n.selection, .system)
    }
    func testCatalogCompletenessAndPlaceholderParity() throws {
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        XCTAssertGreaterThan(english.count, 400)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let placeholders = try NSRegularExpression(pattern: #"\{[0-9]+\}|%[0-9.]*[df]"#)
        func tokens(_ value: String) -> [String] {
            let string = value as NSString
            return placeholders.matches(in: value, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }.sorted()
        }
        for (key, value) in english {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertEqual(tokens(value), tokens(chinese[key]!), key)
        }
    }
    private func catalog(_ name: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
}
