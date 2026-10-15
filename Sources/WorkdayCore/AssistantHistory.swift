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
    public var localizedContents: [String: String]?
    public var displayedContent: String {
        localizedContents?[L10n.selection.resolved().rawValue] ?? content
    }
    public init(role: Role, content: String, complete: Bool = true, proactive: Bool = false) {
        id = UUID(); date = Date(); self.role = role; self.content = content; self.complete = complete
        self.proactive = proactive ? true : nil
    }
}

public enum AssistantHistory {
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
