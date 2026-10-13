import Foundation

public enum WorkState: String { case before, working, lunch, after, rest
    public var title: String { switch self { case .before: return L10n.text("未上班"); case .working: return L10n.text("工作中"); case .lunch: return L10n.text("午休"); case .after: return L10n.text("已下班"); case .rest: return L10n.text("休息日") } }
}
public struct WorkSnapshot {
    public let dateKey: String
    public let state: WorkState
    public let start: Date
    public let end: Date
    public let intervals: [DateInterval]
    public let totalSeconds: TimeInterval
    public let workedSeconds: TimeInterval
    public let remaining: TimeInterval
    public var progress: Double { totalSeconds > 0 ? min(1, max(0, workedSeconds / totalSeconds)) : 0 }
}
public enum ScheduleCalculator {
    public static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(from key: String, calendar: Calendar) -> Date? {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), self.key(date, calendar: calendar) == key else { return nil }
        return date
    }
    public static func isWorkday(_ date: Date, settings: WorkSettings) -> Bool {
        settings.overrides[key(date, calendar: settings.calendar)] ?? settings.weekdays.contains(settings.calendar.component(.weekday, from: date))
    }
    /// Calendar resolves gaps to the next valid local time and folds to their first occurrence.
    public static func localTime(_ minute: Int, on date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.nextDate(after: day.addingTimeInterval(-1), matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }
    public static func snapshot(now: Date, settings: WorkSettings) -> WorkSnapshot {
        let c = settings.calendar
        let start = localTime(settings.startMinute(on: now), on: now, calendar: c)
        let end = localTime(settings.endMinute(on: now), on: now, calendar: c)
        let b1 = localTime(settings.lunchStart, on: now, calendar: c)
        let b2 = localTime(settings.lunchEnd, on: now, calendar: c)
        // A DST gap can collapse an interval even if its wall-clock times are valid.
        let ranges = settings.lunchEnabled ? [(start, min(b1, end)), (max(start, b2), end)] : [(start, end)]
        let intervals = ranges.compactMap { $0.1 > $0.0 ? DateInterval(start: $0.0, end: $0.1) : nil }
        let total = intervals.reduce(0) { $0 + $1.duration }
        let workday = isWorkday(now, settings: settings)
        let state: WorkState = !workday ? .rest : now < start ? .before : now >= end ? .after : settings.lunchEnabled && now >= b1 && now < b2 ? .lunch : .working
        let worked = workday ? intervals.reduce(0) { $0 + min($1.duration, max(0, now.timeIntervalSince($1.start))) } : 0
        return WorkSnapshot(dateKey: key(now, calendar: c), state: state, start: start, end: end, intervals: intervals, totalSeconds: total, workedSeconds: worked, remaining: max(0, end.timeIntervalSince(now)))
    }
    public static func plannedDays(now: Date, settings: WorkSettings) -> Int {
        let c = settings.calendar; let month = c.dateInterval(of: .month, for: now)!
        var day = month.start; var count = 0
        while day < month.end { if isWorkday(day, settings: settings) { count += 1 }; day = c.date(byAdding: .day, value: 1, to: day)! }
        return count
    }
    public static func timeLabel(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public static func countdown(_ seconds: TimeInterval, secondsIncluded: Bool = false) -> String {
        if seconds <= 0 { return secondsIncluded ? "00:00:00" : "00:00" }
        if secondsIncluded { let s = Int(ceil(seconds)); return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        if seconds < 60 { return L10n.text("<1分钟") }
        let m = Int(ceil(seconds / 60)); return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
public struct EarningsSnapshot { public let daily: Decimal?; public let earned: Decimal?; public let reason: String? }
public enum EarningsCalculator {
    public static func calculate(now: Date, settings: WorkSettings, work: WorkSnapshot) -> EarningsSnapshot {
        let daily: Decimal
        switch settings.payMode {
        case .customDaily:
            guard let value = settings.customDaily else { return EarningsSnapshot(daily: nil, earned: nil, reason: L10n.text("设置自定义日薪后查看今日收入")) }; daily = value
        case .fixedDays, .plannedDays:
            guard let salary = settings.monthlySalary else { return EarningsSnapshot(daily: nil, earned: nil, reason: L10n.text("设置月薪后查看今日收入")) }
            let divisor = settings.payMode == .fixedDays ? settings.fixedDays : Decimal(ScheduleCalculator.plannedDays(now: now, settings: settings))
            guard divisor > 0 else { return EarningsSnapshot(daily: nil, earned: nil, reason: L10n.text("当月计划工作日为 0，请修改工作安排")) }
            daily = salary / divisor
        }
        if work.state == .rest { return EarningsSnapshot(daily: 0, earned: 0, reason: nil) }
        guard work.totalSeconds > 0 else { return EarningsSnapshot(daily: nil, earned: nil, reason: L10n.text("当天有效工时为 0（时区时间跳变），请修改安排")) }
        // Convert absolute durations once; never accumulate rounded money on timer ticks.
        let earned = daily * Decimal(work.workedSeconds) / Decimal(work.totalSeconds)
        return EarningsSnapshot(daily: daily, earned: earned, reason: nil)
    }
}
public enum DisplayFormatter {
    public static func menu(settings: WorkSettings, work: WorkSnapshot, earnings: EarningsSnapshot) -> String {
        if settings.menuMode == .icon { return "" }
        if work.state == .rest { return L10n.text("休息日") }
        if settings.menuMode == .earnings {
            guard let earned = earnings.earned else { return settings.payMode == .customDaily ? L10n.text("待设置日薪") : settings.monthlySalary != nil ? L10n.text("无法估算工资") : L10n.text("待设置月薪") }
            return L10n.text("今日 ") + (settings.hideEarnings ? "¥••••" : Money.formatted(earned))
        }
        switch work.state {
        case .before, .after, .rest: return work.state.title
        case .working, .lunch: return (work.state == .lunch ? L10n.text("午休 · ") : "") + L10n.text("下班 ") + ScheduleCalculator.countdown(work.remaining)
        }
    }
}
