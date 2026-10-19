import Foundation

/// A complete input snapshot. The host owns the clock, settings, and persisted state.
public struct AIBotContext {
    public let now: Date
    public let settings: WorkSettings
    public let checkout: CheckoutRecord?
    public let checklistItems: [BotTodo]
    public let hydration: HydrationSummary
    public let ledger: ReminderLedger
    public let pause: ReminderPause?
    public init(now: Date, settings: WorkSettings, checkout: CheckoutRecord? = nil,
                hydration: HydrationSummary = .init(cups: 0, totalML: 0),
                ledger: ReminderLedger = .init(), pause: ReminderPause? = nil, checklistItems: [BotTodo] = []) {
        self.now = now; self.settings = settings; self.checkout = checkout
        self.checklistItems = checklistItems
        self.hydration = hydration; self.ledger = ledger; self.pause = pause
    }
}

public struct AIBotSnapshot {
    public let work: WorkSnapshot
    public let earnings: EarningsSnapshot
    public let checkout: CheckoutSnapshot
    public let report: DailyReport
    public let activePause: ReminderPause?
    public let overtimeNotice: String?
}

public struct AIBotMessage: Codable, Equatable {
    public struct Text: Codable, Equatable {
        public let title: String
        public let body: String
        public var content: String { title.isEmpty ? body : title + "\n" + body }
        public init(title: String = "", body: String) { self.title = title; self.body = body }
    }
    public let id: String
    public let date: Date
    public let translations: [String: Text]
    public var localizedContents: [String: String] { translations.mapValues(\.content) }
    public func text(language: AppLanguage = L10n.selection) -> Text {
        translations[language.resolved().rawValue] ?? translations[AppLanguage.english.rawValue] ?? Text(body: "")
    }
}

public struct AIBotReminder: Codable, Equatable {
    public let event: ReminderEvent
    public let message: AIBotMessage
    public let speak: Bool
    public let healthMessageKey: String?
}

public enum AIBotEvent: Codable, Equatable {
    case checkout
    case startup
    case reminder(ReminderEvent)
}

/// Commands describe intent; only a platform adapter performs storage, UI, or notification work.
public enum AIBotAction: Codable, Equatable {
    case recordCheckout(CheckoutRecord)
    case showMessagePanel
    case postMessage(AIBotMessage)
    case deliverReminder(AIBotReminder)
}

/// The local automation entry point. No UI, disk access, credentials, or network requests.
public struct AIBot: Sendable {
    public init() {}
    public func inspect(_ context: AIBotContext) -> AIBotSnapshot {
        let work = ScheduleCalculator.snapshot(now: context.now, settings: context.settings)
        let checkout = OvertimeCalculator.snapshot(now: context.now, settings: context.settings, work: work, checkout: context.checkout)
        let shouldShowOvertime = context.settings.overtimeEnabled && checkout.isOvertime
            && checkout.overtimeSeconds >= OvertimeCalculator.reminderInterval(settings: context.settings)
        return AIBotSnapshot(work: work,
            earnings: EarningsCalculator.calculate(now: context.now, settings: context.settings, work: work),
            checkout: checkout,
            report: DailyReport.snapshot(now: context.now, settings: context.settings, checkout: context.checkout, hydration: context.hydration, checklistItems: context.checklistItems),
            activePause: context.pause?.active(now: context.now, settings: context.settings) == true ? context.pause : nil,
            overtimeNotice: shouldShowOvertime ? OvertimeCalculator.message(seconds: checkout.overtimeSeconds, intervalMinutes: context.settings.overtimeIntervalMinutes) : nil)
    }
    public func handle(_ event: AIBotEvent, in context: AIBotContext) -> [AIBotAction] {
        switch event {
        case .checkout:
            guard inspect(context).checkout.canCheckout else { return [] }
            let checkout = CheckoutRecord(now: context.now, settings: context.settings)
            let report = DailyReport.snapshot(now: context.now, settings: context.settings, checkout: checkout, hydration: context.hydration, checklistItems: context.checklistItems)
            return [.recordCheckout(checkout), .showMessagePanel, .postMessage(dailyReportMessage(report, hideEarnings: context.settings.hideEarnings))]
        case .startup:
            guard let reminder = ReminderPlanner.startupEvent(now: context.now, settings: context.settings,
                ledger: context.ledger, pause: context.pause, checkout: context.checkout) else { return [] }
            return handle(.reminder(reminder), in: context)
        case .reminder(let reminder):
            guard ReminderPlanner.due(reminder, now: context.now, settings: context.settings, ledger: context.ledger,
                pause: context.pause, checkout: context.checkout) else { return [] }
            let key = reminder.kind == .hourly ? L10n.sourceKey(for: HealthMessages.choose(categories: context.settings.categories,
                previous: context.ledger.lastMessage.map { L10n.text(L10n.sourceKey(for: $0)) })) : nil
            return [.deliverReminder(AIBotReminder(event: reminder,
                message: reminderMessage(reminder, settings: context.settings, healthMessageKey: key),
                speak: reminder.kind == .hourly && context.settings.speechEnabled, healthMessageKey: key))]
        }
    }
    public func nextReminder(in context: AIBotContext) -> ReminderEvent? {
        ReminderPlanner.next(now: context.now, settings: context.settings, ledger: context.ledger, pause: context.pause, checkout: context.checkout)
    }
    /// Recheck immediately before an asynchronous notification is submitted.
    public func mayDeliver(_ event: ReminderEvent, in context: AIBotContext) -> Bool {
        !(context.checkout?.applies(now: context.now, settings: context.settings) ?? false)
            && ReminderPlanner.allowed(event, settings: context.settings, pause: context.pause, checkout: context.checkout)
    }
    public func upcomingOffwork(in context: AIBotContext, days: Int = 7) -> [ReminderEvent] {
        guard context.settings.offworkEnabled else { return [] }
        let calendar = context.settings.calendar
        let today = calendar.startOfDay(for: context.now)
        return (0..<max(0, min(370, days))).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  ScheduleCalculator.isWorkday(day, settings: context.settings) else { return nil }
            let end = ScheduleCalculator.localTime(context.settings.endMinute(on: day), on: day, calendar: calendar)
            let event = ReminderPlanner.event(date: end, kind: .offwork, settings: context.settings)
            let future = AIBotContext(now: end, settings: context.settings, checkout: context.checkout, pause: context.pause)
            guard end > context.now, mayDeliver(event, in: future) else { return nil }
            return event
        }
    }
    public func importHolidayNotice(_ text: String, year: Int) throws -> HolidayImportResult {
        try HolidayNoticeParser.parse(text, year: year)
    }
    public func dailyReportMessage(_ report: DailyReport, hideEarnings: Bool) -> AIBotMessage {
        message(id: "report." + report.id, date: report.checkedOutAt ?? report.updatedAt) {
            AIBotMessage.Text(body: report.assistantReport(hideEarnings: hideEarnings, language: $0))
        }
    }
    public func testReminder(settings: WorkSettings, now: Date) -> AIBotMessage {
        let key = settings.hourlyEnabled ? L10n.sourceKey(for: HealthMessages.choose(categories: settings.categories, previous: nil)) : "工作辛苦了，记得适当休息"
        return message(id: "test." + UUID().uuidString, date: now) {
            AIBotMessage.Text(title: L10n.text("测试提醒", language: $0), body: L10n.text(key, language: $0))
        }
    }
    public func reminderMessage(_ event: ReminderEvent, settings: WorkSettings, healthMessageKey: String? = nil) -> AIBotMessage {
        message(id: event.id, date: event.date) { language in
            switch event.kind {
            case .offwork:
                return AIBotMessage.Text(title: L10n.text("下班啦", language: language), body: L10n.text("下班时间到啦！点击“打卡下班”，今天辛苦了。", language: language))
            case .overtime:
                let work = ScheduleCalculator.snapshot(now: event.date, settings: settings)
                return AIBotMessage.Text(title: L10n.text("加班提醒 · 下班啦", language: language),
                    body: OvertimeCalculator.message(seconds: event.date.timeIntervalSince(work.end), intervalMinutes: settings.overtimeIntervalMinutes, language: language))
            case .hourly:
                let hour = settings.calendar.component(.hour, from: event.date)
                let remaining = ScheduleCalculator.snapshot(now: event.date, settings: settings).remaining
                let minutes = Int(ceil(remaining / 60))
                let duration = minutes >= 60
                    ? L10n.format("{0} 小时", String(minutes / 60), language: language) + (minutes % 60 > 0 ? L10n.format(" {0} 分钟", String(minutes % 60), language: language) : "")
                    : L10n.format("{0} 分钟", String(minutes), language: language)
                return AIBotMessage.Text(title: String(format: L10n.text("现在是 %02d:00", language: language), hour),
                    body: L10n.text(healthMessageKey ?? "工作辛苦了，记得适当休息", language: language) + " " + L10n.format("距离下班还有 {0}。", duration, language: language))
            }
        }
    }
    private func message(id: String, date: Date, render: (AppLanguage) -> AIBotMessage.Text) -> AIBotMessage {
        AIBotMessage(id: id, date: date, translations: Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map { ($0.rawValue, render($0)) }))
    }
}
