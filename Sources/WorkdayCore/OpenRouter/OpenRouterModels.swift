import Foundation

/// JSON values for provider options, tools, multimodal content and future API fields.
public enum OpenRouterJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String)
    case array([OpenRouterJSON]), object([String: OpenRouterJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([OpenRouterJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: OpenRouterJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct OpenRouterMessage: Encodable, Sendable {
    public enum Role: String, Sendable { case system, developer, user, assistant, tool }
    public var role: Role
    public var content: OpenRouterJSON
    public var additionalFields: [String: OpenRouterJSON]

    public init(role: Role, content: String) {
        self.init(role: role, content: .string(content))
    }

    public init(role: Role, content: OpenRouterJSON, additionalFields: [String: OpenRouterJSON] = [:]) {
        self.role = role
        self.content = content
        self.additionalFields = additionalFields
    }

    public func encode(to encoder: Encoder) throws {
        var fields = additionalFields
        fields["role"] = .string(role.rawValue)
        fields["content"] = content
        try fields.encode(to: encoder)
    }
}

public struct OpenRouterRequest: Encodable, Sendable {
    public var model: String
    public var messages: [OpenRouterMessage]
    public var temperature: Double?
    public var maxTokens: Int?
    /// e.g. `provider`, `reasoning`, `tools`, `response_format`, `models`.
    /// Core fields take precedence; streaming is always enabled.
    public var additionalParameters: [String: OpenRouterJSON]

    public init(model: String, messages: [OpenRouterMessage], temperature: Double? = nil,
                maxTokens: Int? = nil, additionalParameters: [String: OpenRouterJSON] = [:]) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.additionalParameters = additionalParameters
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in additionalParameters where !["model", "messages", "stream", "temperature", "max_tokens"].contains(key) {
            try container.encode(value, forKey: Key(key))
        }
        try container.encode(model, forKey: Key("model"))
        try container.encode(messages, forKey: Key("messages"))
        try container.encode(true, forKey: Key("stream"))
        try container.encodeIfPresent(temperature, forKey: Key("temperature"))
        try container.encodeIfPresent(maxTokens, forKey: Key("max_tokens"))
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
}

public struct OpenRouterChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Delta: Decodable, Sendable {
            public let role: String?
            public let content: String?
            public let reasoning: String?
            public let toolCalls: [OpenRouterJSON]?
            enum CodingKeys: String, CodingKey { case role, content, reasoning; case toolCalls = "tool_calls" }
        }
        public let index: Int
        public let delta: Delta?
        public let finishReason: String?
        enum CodingKeys: String, CodingKey { case index, delta; case finishReason = "finish_reason" }
    }
    public let id: String?
    public let model: String?
    public let choices: [Choice]
    public let usage: OpenRouterJSON?
    /// Full payload preserves fields that are not exposed by the typed convenience properties.
    public let raw: OpenRouterJSON

    public init(from decoder: Decoder) throws {
        raw = try OpenRouterJSON(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try container.decodeIfPresent(OpenRouterJSON.self, forKey: .usage)
    }
    private enum CodingKeys: String, CodingKey { case id, model, choices, usage }
}

public enum OpenRouterError: Error, Sendable {
    case invalidRequest(String)
    case invalidResponse
    case unexpectedContentType(String?)
    case http(statusCode: Int, body: String)
    case api(code: OpenRouterJSON?, message: String)
    case malformedEvent(String)
    case eventTooLarge
    case incompleteStream
}

extension OpenRouterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return "请求配置无效，请检查模型与 API Key。"
        case .invalidResponse: return "OpenRouter 返回了无法识别的响应。"
        case .unexpectedContentType(let type): return "接口未返回 SSE 流（Content-Type：\(type ?? "缺失")）。"
        case .http(let status, let body):
            var message = ""
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any], let detail = error["message"] as? String { message = detail }
            let advice: String
            switch status {
            case 401: advice = "API Key 无效或已过期，请在 AI 助手设置中重新保存。"
            case 402: advice = "账户额度不足，请检查 OpenRouter 余额或选择免费模型。"
            case 403: advice = "请求被拒绝，请检查账户权限或模型限制。"
            case 404: advice = "模型不可用，请刷新模型列表并重新选择。"
            case 429: advice = "模型限流或免费额度已用完，请稍后重试或在 AI 助手设置中更换模型。"
            case 500...599: advice = "模型服务暂时不可用，请稍后重试或更换模型。"
            default: advice = "请求失败，请检查模型设置。"
            }
            return "OpenRouter HTTP \(status)：\(advice)" + (message.isEmpty ? "" : "\n\(String(message.prefix(500)))")
        case .api(_, let message): return "OpenRouter：\(String(message.prefix(500)))"
        case .malformedEvent: return "收到无法解析的流式响应，请重试或更换模型。"
        case .eventTooLarge: return "单条流式响应超过大小限制。"
        case .incompleteStream: return "连接在回复结束前断开，已保留收到的内容，请稍后重试。"
        }
    }
}
