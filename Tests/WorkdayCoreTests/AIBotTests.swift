import XCTest
@testable import WorkdayCore

final class AIBotTests: ChineseLocalizationTestCase {
    private let bot = AIBot()
    private let helper = CalculationTests()
    private func context(_ time: String = "11:00:00", settings: WorkSettings? = nil,
                         checkout: CheckoutRecord? = nil, ledger: ReminderLedger = .init(), pause: ReminderPause? = nil) -> AIBotContext {
        AIBotContext(now: helper.date("2026-10-12 " + time), settings: settings ?? helper.settings(), checkout: checkout,
            hydration: .init(cups: 3, totalML: 1500), ledger: ledger, pause: pause)
    }
    func testCheckoutProducesImmediateLocalActionsAndACompleteBilingualReport() throws {
        let input = context("18:20:00")
        let actions = bot.handle(.checkout, in: input)
        XCTAssertEqual(actions.count, 3)
        guard case .recordCheckout(let record) = actions[0],
              case .showMessagePanel = actions[1], case .postMessage(let message) = actions[2] else {
            return XCTFail("Expected checkout persistence, panel presentation, then local pet message")
        }
        XCTAssertEqual(record.checkedOutAt, input.now)
        XCTAssertEqual(message.date, input.now)
        XCTAssertTrue(message.text(language: .english).body.contains("Overtime: 20min"))
        XCTAssertTrue(message.text(language: .simplifiedChinese).body.contains("今天喝了1500ml水"))
        XCTAssertEqual(try JSONDecoder().decode([AIBotAction].self, from: JSONEncoder().encode(actions)), actions)
        XCTAssertTrue(bot.handle(.checkout, in: context("18:21:00", checkout: record)).isEmpty)
    }
    func testCheckoutIsUnavailableBeforeWorkAndOnRestDays() {
        XCTAssertTrue(bot.handle(.checkout, in: context("08:59:59")).isEmpty)
        let rest = AIBotContext(now: helper.date("2026-10-17 18:00:00"), settings: helper.settings())
        XCTAssertTrue(bot.handle(.checkout, in: rest).isEmpty)
    }
    func testReportFreezesAtCheckoutAndDoesNotLeakHiddenEarnings() {
        let settings = helper.settings()
        let record = CheckoutRecord(now: helper.date("2026-10-12 15:00:00"), settings: settings)
        let snapshot = bot.inspect(context("20:00:00", checkout: record))
        XCTAssertEqual(snapshot.report.earned, 625)
        XCTAssertEqual(snapshot.report.overtimeSeconds, 0)
        let message = bot.dailyReportMessage(snapshot.report, hideEarnings: true)
        for text in message.localizedContents.values { XCTAssertFalse(text.contains("625")) }
    }
    func testDueReminderProducesOneConsistentMessageForAllChannels() throws {
        var settings = helper.settings(); settings.speechEnabled = true; settings.categories = [.water]
        let input = context(settings: settings)
        let event = ReminderPlanner.event(date: input.now, kind: .hourly, settings: settings)
        let actions = bot.handle(.reminder(event), in: input)
        guard case .deliverReminder(let reminder) = try XCTUnwrap(actions.first) else { return XCTFail() }
        XCTAssertTrue(reminder.speak)
        XCTAssertNotNil(reminder.healthMessageKey)
        XCTAssertEqual(reminder.message.id, event.id)
        XCTAssertTrue(reminder.message.text(language: .english).body.contains("7 hours until"))
        for language in [AppLanguage.english, .simplifiedChinese] {
            let text = reminder.message.text(language: language)
            XCTAssertEqual(reminder.message.localizedContents[language.rawValue], text.title + "\n" + text.body)
        }
        var ledger = input.ledger; ledger.consume(event)
        XCTAssertTrue(bot.handle(.reminder(event), in: context(settings: settings, ledger: ledger)).isEmpty)
    }
    func testPausedLateDisabledAndCheckedOutRemindersDoNotFire() {
        let input = context()
        let event = ReminderPlanner.event(date: input.now, kind: .hourly, settings: input.settings)
        let pause = ReminderPause(until: helper.date("2026-10-12 12:00:00"), dateKey: "2026-10-12")
        XCTAssertTrue(bot.handle(.reminder(event), in: context(pause: pause)).isEmpty)
        XCTAssertTrue(bot.handle(.reminder(event), in: context("11:00:11")).isEmpty)
        var disabled = input.settings; disabled.hourlyEnabled = false
        XCTAssertTrue(bot.handle(.reminder(event), in: context(settings: disabled)).isEmpty)
        let checkout = CheckoutRecord(now: helper.date("2026-10-12 10:00:00"), settings: input.settings)
        XCTAssertTrue(bot.handle(.reminder(event), in: context(checkout: checkout)).isEmpty)
        XCTAssertFalse(bot.mayDeliver(event, in: context(checkout: checkout)))
    }
    func testStartupOnlyDeliversWithinExistingGracePeriod() {
        XCTAssertEqual(bot.handle(.startup, in: context("11:00:05")).count, 1)
        XCTAssertTrue(bot.handle(.startup, in: context("11:00:11")).isEmpty)
    }
    func testSnapshotOwnsPauseExpiryAndOvertimeNoticeThreshold() {
        let pause = ReminderPause(until: helper.date("2026-10-12 12:00:00"), dateKey: "2026-10-12")
        XCTAssertEqual(bot.inspect(context(pause: pause)).activePause, pause)
        XCTAssertNil(bot.inspect(context("12:00:00", pause: pause)).activePause)
        var settings = helper.settings(); settings.overtimeEnabled = true
        XCTAssertNil(bot.inspect(context("18:04:59", settings: settings)).overtimeNotice)
        XCTAssertNotNil(bot.inspect(context("18:05:00", settings: settings)).overtimeNotice)
        let checkout = CheckoutRecord(now: helper.date("2026-10-12 18:05:00"), settings: settings)
        XCTAssertNil(bot.inspect(context("18:06:00", settings: settings, checkout: checkout)).overtimeNotice)
    }
    func testHolidayImportAffectsWorkStateAndReminderPlanning() throws {
        let parsed = try bot.importHolidayNotice(HolidayImportTests.notices[2026]!, year: 2026)
        var settings = helper.settings(); settings.overrides = parsed.overrides
        let holiday = AIBotContext(now: helper.date("2026-01-01 11:00:00"), settings: settings)
        XCTAssertEqual(bot.inspect(holiday).work.state, .rest)
        let event = ReminderPlanner.event(date: holiday.now, kind: .hourly, settings: settings)
        XCTAssertTrue(bot.handle(.reminder(event), in: holiday).isEmpty)
        let next = try XCTUnwrap(bot.nextReminder(in: holiday))
        XCTAssertEqual(ScheduleCalculator.key(next.date, calendar: settings.calendar), "2026-01-04")
        XCTAssertEqual(bot.inspect(AIBotContext(now: next.date, settings: settings)).work.state, .working)
    }
    func testOffworkPlanningSkipsCheckedOutTodayButRetainsTomorrow() {
        let settings = helper.settings()
        let record = CheckoutRecord(now: helper.date("2026-10-12 16:00:00"), settings: settings)
        let upcoming = bot.upcomingOffwork(in: context("17:00:00", checkout: record), days: 2)
        XCTAssertEqual(upcoming.count, 1)
        XCTAssertEqual(ScheduleCalculator.key(upcoming[0].date, calendar: settings.calendar), "2026-10-13")
        var disabled = settings; disabled.offworkEnabled = false
        XCTAssertTrue(bot.upcomingOffwork(in: context(settings: disabled)).isEmpty)
    }
    func testOffworkAndOvertimeCopyRemainBilingualAndSpeechRulesStayUnchanged() throws {
        var settings = helper.settings(); settings.overtimeEnabled = true; settings.speechEnabled = true
        for (time, kind) in [("18:00:00", EventKind.offwork), ("18:05:00", .overtime)] {
            let input = context(time, settings: settings)
            let event = ReminderPlanner.event(date: input.now, kind: kind, settings: settings)
            guard case .deliverReminder(let reminder) = try XCTUnwrap(bot.handle(.reminder(event), in: input).first) else { return XCTFail() }
            XCTAssertFalse(reminder.speak)
            XCTAssertNil(reminder.message.text(language: .english).body.range(of: "\\p{Han}", options: .regularExpression))
        }
    }
}
