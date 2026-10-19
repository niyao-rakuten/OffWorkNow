import Foundation

public struct BotDietEntry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public let date: Date
    public let text: String
    public init(date: Date, text: String) { self.date = date; self.text = text }
}
public struct BotTodo: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var done = false
    public var due: Date?
    public var originID: UUID?
    public var delivered = false
    public init(text: String, due: Date? = nil) { self.text = text; self.due = due }
    public func edited(text: String? = nil, done: Bool? = nil) throws -> BotTodo {
        var next = self
        if let text {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw ValidationError(L10n.text("待办事项不能为空。")) }
            next.text = value
        }
        if let done { next.done = done }
        return next
    }
}
public struct BotChecklist: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var items: [BotTodo]
    public init(items: [BotTodo] = []) { self.items = items }
}
public enum LocalBotIntent: Equatable {
    case information(BotInformationRequest)
    case diet(String, Date), dietSummary(Date), reminder(String, Date), checklist([String]), clarification(String)
}
extension AIBot {
    /// Conservative, deterministic routing. Nil is the only route to the cloud.
    public func interpret(_ input: String, now: Date, calendar: Calendar = .current) -> LocalBotIntent? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        if let request = BotInformationRequest.interpret(text) { return .information(request) }
        let directChecklist = match(#"^(?:(?:today(?:'s)?\s+)?(?:todo(?:\s+list)?|checklist)|(?:(?:今天|今日)的?)?待办(?:清单|列表)?)(?:\s*[:：].*)?\s*$"#) != nil
        if directChecklist || match(#"^(?:请|帮我)?(?:创建|新建|建一个|创建一个|建|create|make|帮我创建一个).*?(?:checklist|todo|待办清单|待办列表|清单)"#) != nil {
            let suffix = text.range(of: #"(?:checklist|todo(?:\s+(?:checklist|list))?|待办清单|待办列表|清单)\s*[:：]?\s*"#, options: [.regularExpression, .caseInsensitive]).map { String(text[$0.upperBound...]) } ?? ""
            let items = suffix.components(separatedBy: CharacterSet(charactersIn: "\n,，、;；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return .checklist(items)
        }
        if match(#"^(?:请|帮我)?提醒我|^remind me\b"#) != nil {
            if let m = match(#"^(?:请|帮我)?提醒我\s*(今天|明天|后天)?\s*(上午|下午|晚上)?\s*(\d{1,2})(?:[:：](\d{2})|点(?:(\d{1,2})分?)?)\s*(.+)$"#) {
                var hour = Int(m[3]) ?? 99
                let minute = Int(m[4].isEmpty ? (m[5].isEmpty ? "0" : m[5]) : m[4]) ?? 99
                if ["下午", "晚上"].contains(m[2]), hour < 12 { hour += 12 }
                guard hour < 24, minute < 60 else { return .clarification("请输入有效时间，例如：提醒我明天14:00回归测试。") }
                let offset = m[1] == "明天" ? 1 : m[1] == "后天" ? 2 : 0
                let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
                guard let due = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), due > now else { return .clarification("这个时间已经过去了，请注明明天或重新设置时间。") }
                return .reminder(m[6], due)
            }
            if let m = match(#"^remind me\s+(today|tomorrow)?\s*(?:at\s+)?(\d{1,2}):(\d{2})\s+(?:to\s+)?(.+)$"#), let hour = Int(m[2]), let minute = Int(m[3]), hour < 24, minute < 60 {
                let day = calendar.date(byAdding: .day, value: m[1].lowercased() == "tomorrow" ? 1 : 0, to: now) ?? now
                if let due = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), due > now { return .reminder(m[4], due) }
                return .clarification("这个时间已经过去了，请注明明天或重新设置时间。")
            }
            return .clarification("请输入有效时间，例如：提醒我明天14:00回归测试。")
        }
        let day = calendar.date(byAdding: .day, value: text.contains("昨天") || text.lowercased().contains("yesterday") ? -1 : 0, to: now) ?? now
        if match(#"^(?:(?:帮我|请)?(?:统计|查看|总结).*(?:饮食|吃了|喝了)|(?:今天|昨天)的?饮食(?:统计|记录|总结)?[？?]?\s*$|(?:show|summarize).*(?:diet|food|meals))"#) != nil { return .dietSummary(day) }
        if match(#"^(?:(?:我)?(?:今天|昨天).*(?:吃了|喝了).*(?:什么|多少)|what.*(?:eat|drink).*(?:today|yesterday))"#) != nil { return .dietSummary(day) }
        if text.contains("？") || text.hasSuffix("?") { return nil }
        if match(#"^(?:(?:我)?(?:今天|昨天)?(?:早餐|午餐|晚餐|早上|中午|晚上)?(?:吃了|喝了)|(?:today\s+|yesterday\s+)?i\s+(?:ate|drank)\s+)"#) != nil { return .diet(text, day) }
        return nil
    }
}
