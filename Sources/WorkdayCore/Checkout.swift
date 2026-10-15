import Foundation

/// Only the latest local checkout is stored, not an attendance history or payroll ledger.
public struct CheckoutRecord: Codable, Equatable, Sendable {
    public let dateKey: String
    public let timeZoneID: String
    public let checkedOutAt: Date
    public init(now: Date, settings: WorkSettings) {
        dateKey = ScheduleCalculator.key(now, calendar: settings.calendar)
        timeZoneID = settings.timeZoneID; checkedOutAt = now
    }
    public func applies(now: Date, settings: WorkSettings) -> Bool {
        dateKey == ScheduleCalculator.key(now, calendar: settings.calendar) && timeZoneID == settings.timeZoneID && checkedOutAt <= now
    }
}
public struct CheckoutSnapshot {
    public let isCheckedOut: Bool
    public let canCheckout: Bool
    public let overtimeSeconds: TimeInterval
    public var isOvertime: Bool { overtimeSeconds > 0 && !isCheckedOut }
    public var duration: String { OvertimeCalculator.duration(overtimeSeconds) }
}
public enum OvertimeCalculator {
    public static let interval: TimeInterval = 300
    public static func reminderInterval(settings: WorkSettings) -> TimeInterval { TimeInterval(settings.overtimeIntervalMinutes) * 60 }
    public static func parseInterval(_ input: String) throws -> Int {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, let value = Int(text), (1...240).contains(value) else { throw ValidationError(L10n.text("加班提示间隔须为 1–240 分钟的整数")) }
        return value
    }
    public static func snapshot(now: Date, settings: WorkSettings, work: WorkSnapshot, checkout: CheckoutRecord?) -> CheckoutSnapshot {
        let checked = checkout?.applies(now: now, settings: settings) ?? false
        let cutoff = checked ? checkout!.checkedOutAt : now
        let overtime = work.state == .rest ? 0 : max(0, cutoff.timeIntervalSince(work.end))
        return CheckoutSnapshot(isCheckedOut: checked, canCheckout: !checked && work.state != .before && work.state != .rest, overtimeSeconds: overtime)
    }
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes / 60)h\(minutes % 60)min"
    }
    public static func message(seconds: TimeInterval, intervalMinutes: Int = 5, language: AppLanguage? = nil) -> String {
        let step = max(1, Int(seconds / (TimeInterval(max(1, intervalMinutes)) * 60)))
        let time = duration(seconds)
        return step.isMultiple(of: 2) ? L10n.format("已经加班{0}！不要再当牛马了，快点下班", String(describing: time), language: language) : L10n.format("你怎么又在加班？已经加班{0}了", String(describing: time), language: language)
    }
    public static func next(now: Date, settings: WorkSettings, checkout: CheckoutRecord?, ledger: ReminderLedger) -> ReminderEvent? {
        guard settings.overtimeEnabled, !(checkout?.applies(now: now, settings: settings) ?? false) else { return nil }
        let interval = reminderInterval(settings: settings)
        guard interval > 0 else { return nil }
        let work = ScheduleCalculator.snapshot(now: now, settings: settings)
        guard work.state != .rest else { return nil }
        let tomorrow = settings.calendar.date(byAdding: .day, value: 1, to: settings.calendar.startOfDay(for: now))!
        var step = max(1, Int(max(0, now.timeIntervalSince(work.end)) / interval) + 1)
        while true {
            let date = work.end.addingTimeInterval(Double(step) * interval)
            guard date < tomorrow else { return nil }
            let id = "overtime.\(settings.timeZoneID).\(work.dateKey).\(Int(Double(step) * interval))"
            if ledger.records[id] == nil { return ReminderEvent(id: id, date: date, kind: .overtime) }
            step += 1
        }
    }
}
