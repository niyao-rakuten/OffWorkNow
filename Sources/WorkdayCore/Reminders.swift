import Foundation

public struct ReminderPause: Codable, Equatable {
    public let until: Date
    public let dateKey: String
    public init(until: Date, dateKey: String) { self.until = until; self.dateKey = dateKey }
    public func active(now: Date, settings: WorkSettings) -> Bool { now < until && dateKey == ScheduleCalculator.key(now, calendar: settings.calendar) }
}
public enum EventKind: String, Codable, Sendable { case hourly, offwork, overtime }
public struct ReminderEvent: Codable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let kind: EventKind
    public init(id: String, date: Date, kind: EventKind) { self.id = id; self.date = date; self.kind = kind }
}
public struct EventRecord: Codable, Equatable {
    public var notification: String
    public var speech: String
    public init(notification: String = "skipped", speech: String = "skipped") { self.notification = notification; self.speech = speech }
}
public struct ReminderLedger: Codable {
    public var records: [String: EventRecord] = [:]
    public var lastMessage: String? = nil
    public init() {}
    public mutating func consume(_ event: ReminderEvent, record: EventRecord = EventRecord()) { records[event.id] = record }
}
public enum ReminderPlanner {
    public static func event(date: Date, kind: EventKind, settings: WorkSettings) -> ReminderEvent {
        let key = ScheduleCalculator.key(date, calendar: settings.calendar)
        if kind == .overtime {
            let end = ScheduleCalculator.localTime(settings.endMinute(on: date), on: date, calendar: settings.calendar)
            let elapsed = Int(date.timeIntervalSince(end))
            return ReminderEvent(id: "overtime.\(settings.timeZoneID).\(key).\(elapsed)", date: date, kind: kind)
        }
        let id = kind == .offwork ? "offwork.\(settings.timeZoneID).\(key)" : "hourly.\(settings.timeZoneID).\(key).\(settings.calendar.component(.hour, from: date))"
        return ReminderEvent(id: id, date: date, kind: kind)
    }
    public static func allowed(_ event: ReminderEvent, settings: WorkSettings, pause: ReminderPause?, checkout: CheckoutRecord? = nil) -> Bool {
        guard event.id == self.event(date: event.date, kind: event.kind, settings: settings).id else { return false }
        if checkout?.applies(now: event.date, settings: settings) == true { return false }
        let work = ScheduleCalculator.snapshot(now: event.date, settings: settings)
        if event.kind == .overtime {
            let seconds = event.date.timeIntervalSince(work.end)
            return settings.overtimeEnabled && work.state == .after && seconds >= OvertimeCalculator.reminderInterval(settings: settings) && abs(seconds.truncatingRemainder(dividingBy: OvertimeCalculator.reminderInterval(settings: settings))) < 0.001
        }
        if event.kind == .offwork { return settings.offworkEnabled && work.state != .rest && abs(event.date.timeIntervalSince(work.end)) < 0.001 }
        return settings.hourlyEnabled && work.state == .working && !(pause?.active(now: event.date, settings: settings) ?? false)
    }
    public static func startupEvent(now: Date, settings: WorkSettings, ledger: ReminderLedger, pause: ReminderPause?, checkout: CheckoutRecord? = nil) -> ReminderEvent? {
        let c = settings.calendar
        guard let hour = c.dateInterval(of: .hour, for: now)?.start, c.component(.minute, from: hour) == 0, now.timeIntervalSince(hour) <= 10 else { return nil }
        let event = event(date: hour, kind: .hourly, settings: settings)
        return allowed(event, settings: settings, pause: pause, checkout: checkout) && ledger.records[event.id] == nil ? event : nil
    }
    public static func due(_ event: ReminderEvent, now: Date, settings: WorkSettings, ledger: ReminderLedger, pause: ReminderPause?, checkout: CheckoutRecord? = nil) -> Bool {
        let lag = now.timeIntervalSince(event.date)
        return !(checkout?.applies(now: now, settings: settings) ?? false) && lag >= 0 && lag <= 10 && ledger.records[event.id] == nil && allowed(event, settings: settings, pause: pause, checkout: checkout)
    }
    public static func next(now: Date, settings: WorkSettings, ledger: ReminderLedger, pause: ReminderPause?, checkout: CheckoutRecord? = nil) -> ReminderEvent? {
        let c = settings.calendar
        var day = c.startOfDay(for: now)
        // Date overrides can make an otherwise ordinary workday a rest day.
        for _ in 0..<370 {
            if ScheduleCalculator.isWorkday(day, settings: settings) && !(checkout?.applies(now: max(now, day), settings: settings) ?? false) {
                var events: [ReminderEvent] = []
                if settings.hourlyEnabled {
                    // Iterate actual calendar hours so DST folds/gaps are handled consistently.
                    let nextDay = c.date(byAdding: .day, value: 1, to: day)!
                    var hour = c.nextDate(after: day.addingTimeInterval(-1), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
                    while hour < nextDay {
                        let e = event(date: hour, kind: .hourly, settings: settings)
                        if c.component(.minute, from: hour) == 0 && allowed(e, settings: settings, pause: pause) { events.append(e) }
                        hour = c.nextDate(after: hour, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
                    }
                }
                if settings.offworkEnabled {
                    events.append(event(date: ScheduleCalculator.localTime(settings.endMinute(on: day), on: day, calendar: c), kind: .offwork, settings: settings))
                }
                if let overtime = OvertimeCalculator.next(now: c.isDate(day, inSameDayAs: now) ? now : day, settings: settings, checkout: checkout, ledger: ledger) { events.append(overtime) }
                if let result = events.sorted(by: { $0.date < $1.date }).first(where: { $0.date > now && ledger.records[$0.id] == nil }) { return result }
            }
            day = c.date(byAdding: .day, value: 1, to: day)!
        }
        return nil
    }
}
public enum HealthMessages {
    public static var messages: [ReminderCategory: [String]] { [
        .walk: [L10n.text("站起来走两分钟，活动一下肩背。"), L10n.text("换个姿势，轻轻舒展一下。"), L10n.text("走动一小会儿，再回来继续。"), L10n.text("放松肩膀，起身看看窗外。"), L10n.text("给自己一点活动的时间。"), L10n.text("伸伸懒腰，慢慢走几步。")],
        .water: [L10n.text("喝几口水，休息一下再继续。"), L10n.text("拿起水杯，给自己一个小停顿。"), L10n.text("忙碌之余，记得喝口水。"), L10n.text("慢慢喝点水，放松一下。"), L10n.text("让水杯陪你歇一会儿。"), L10n.text("口渴了就喝点水，照顾好自己。")],
        .eyes: [L10n.text("看看窗外远处，让眼睛歇一会儿。"), L10n.text("暂时离开屏幕，看看远方。"), L10n.text("轻轻眨眨眼，放松视线。"), L10n.text("把目光移向窗外，休息一下。"), L10n.text("给眼睛一点不看屏幕的时间。"), L10n.text("看看远处的景物，稍作休息。")]
    ] }
    public static func choose(categories: Set<ReminderCategory>, previous: String?, pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let available = ReminderCategory.allCases.filter { categories.contains($0) }
        guard !available.isEmpty else { return L10n.text("工作辛苦了，记得适当休息") }
        let category = available[pick(available.count)]
        let candidates = messages[category]!.filter { $0 != previous }
        let pool = candidates.isEmpty ? messages[category]! : candidates
        return pool[pick(pool.count)]
    }
}
