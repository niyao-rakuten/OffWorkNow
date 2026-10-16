import Foundation

public struct AssistantDaySection: Identifiable, Equatable {
    public let date: Date
    public let messages: [AssistantMessage]
    public var id: Date { date }
}
public enum AssistantTimeline {
    public static func today(_ messages: [AssistantMessage], now: Date, calendar: Calendar) -> [AssistantMessage] {
        uniqueGreeting(messages.filter { calendar.isDate($0.date, inSameDayAs: now) })
    }
    /// Page by days that have actual messages, so empty days never require extra pulls.
    public static func sections(_ messages: [AssistantMessage], now: Date, calendar: Calendar, earlierDays: Int) -> [AssistantDaySection] {
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: messages.filter { calendar.startOfDay(for: $0.date) <= today }) { calendar.startOfDay(for: $0.date) }
        let older = grouped.keys.filter { $0 < today }.sorted(by: >).prefix(max(0, earlierDays))
        return (Array(older) + [today]).sorted().compactMap { day in
            guard let entries = grouped[day], !entries.isEmpty else { return nil }
            return AssistantDaySection(date: day, messages: uniqueGreeting(entries.sorted { $0.date < $1.date }))
        }
    }
    private static func uniqueGreeting(_ messages: [AssistantMessage]) -> [AssistantMessage] {
        var seen = false
        return messages.filter { message in
            guard message.isStartupGreeting else { return true }
            if seen { return false }
            seen = true; return true
        }
    }
    public static func earlierDayCount(_ messages: [AssistantMessage], now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        return Set(messages.map { calendar.startOfDay(for: $0.date) }.filter { $0 < today }).count
    }
    public static func dateLabel(_ date: Date, calendar: Calendar, language: AppLanguage = L10n.selection) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: language.resolved().rawValue)
        formatter.dateFormat = language.resolved() == .simplifiedChinese ? "yyyy年MM月dd日 EEEE" : "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

public enum AssistantGreetingPolicy {
    public static func dayKey(now: Date, calendar: Calendar) -> String {
        calendar.timeZone.identifier + "/" + ScheduleCalculator.key(now, calendar: calendar)
    }
    public static func shouldPost(messages: [AssistantMessage], lastPostedDay: String?, now: Date, calendar: Calendar) -> Bool {
        lastPostedDay != dayKey(now: now, calendar: calendar)
            && !messages.contains { $0.isStartupGreeting && calendar.isDate($0.date, inSameDayAs: now) }
    }
}
