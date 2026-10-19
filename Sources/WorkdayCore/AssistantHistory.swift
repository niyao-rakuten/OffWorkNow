import Foundation

public struct AssistantMessage: Codable, Identifiable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let id: UUID
    public let date: Date
    public let role: Role
    public var content: String
    public var usage: AssistantUsage?
    public var modelID: String?
    public var complete: Bool
    public var proactive: Bool?
    public var greetingDay: String?
    public var checklist: BotChecklist?
    public var weather: StartupWeather?
    public var weatherFailure: String?
    public var localizedContents: [String: String]?
    public var displayedContent: String {
        localizedContents?[L10n.selection.resolved().rawValue] ?? content
    }
    public var isStartupGreeting: Bool {
        role == .assistant && proactive == true && (greetingDay != nil || weather != nil || weatherFailure != nil
            || content.contains("又是新的一天") || content.contains("A fresh new day")
            || localizedContents?.values.contains(where: { $0.contains("又是新的一天") || $0.contains("A fresh new day") }) == true)
    }
    public var contextContent: String {
        guard let checklist else { return displayedContent }
        return displayedContent + "\n" + checklist.items.map { "- [" + ($0.done ? "x" : " ") + "] " + $0.text }.joined(separator: "\n")
    }
    public init(role: Role, content: String, complete: Bool = true, proactive: Bool = false, date: Date = Date()) {
        id = UUID(); self.date = date; self.role = role; self.content = content; self.complete = complete
        self.proactive = proactive ? true : nil
    }
}

public enum AssistantHistory {
    public static func checklistItems(_ messages: [AssistantMessage], on date: Date, calendar: Calendar = .current) -> [BotTodo] {
        checklists(messages, on: date, calendar: calendar).flatMap(\.items)
    }
    public static func checklists(_ messages: [AssistantMessage], on date: Date, calendar: Calendar = .current) -> [BotChecklist] {
        var seen = Set<UUID>()
        return messages.filter { $0.role == .assistant && calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap(\.checklist).filter { seen.insert($0.id).inserted }
    }
    public static func updateChecklist(_ messages: inout [AssistantMessage], messageID: UUID, update: (inout BotChecklist) -> Void) {
        guard var checklist = messages.first(where: { $0.id == messageID })?.checklist else { return }
        update(&checklist)
        for index in messages.indices where messages[index].checklist?.id == checklist.id {
            messages[index].checklist = checklist
        }
    }
    public static func save(_ messages: [AssistantMessage], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(messages).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> [AssistantMessage] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AssistantMessage].self, from: Data(contentsOf: url))
    }
}
