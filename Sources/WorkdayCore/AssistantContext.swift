import Foundation

public enum AssistantContext {
    public static let maximumHistoryMessages = 12
    public static let maximumInputBudget = 4096
    public static let maximumOutputTokens = 1024
    /// UTF-8 bytes deliberately overestimate typical text tokens; include message framing overhead.
    public static func isConversationModel(_ id: String?) -> Bool {
        guard let id else { return true }
        let name = id.lowercased()
        return !["content-safety", "safeguard", "guard-", "moderation", "rerank", "embedding"].contains(where: name.contains)
    }
    public static func estimatedTokens(_ text: String) -> Int { text.utf8.count + 24 }
    public static func build(history: [AssistantMessage], system: String, current: String, proactive: Bool = false,
                             inputBudget: Int = maximumInputBudget) throws -> [OpenRouterMessage] {
        var remaining = inputBudget - estimatedTokens(system) - estimatedTokens(current)
        guard remaining >= 0 else { throw ValidationError("消息过长，请缩短后再发送（本次上下文预算 \(inputBudget)）。") }
        if proactive {
            return [OpenRouterMessage(role: .system, content: system), OpenRouterMessage(role: .system, content: current)]
        }
        var pairs: [[AssistantMessage]] = []
        for index in history.indices where history[index].role == .assistant && history[index].complete && !history[index].content.isEmpty && isConversationModel(history[index].modelID) {
            if history[index].proactive == true { pairs.append([history[index]]); continue }
            guard index > 0, history[index - 1].role == .user, history[index - 1].complete else { continue }
            pairs.append([history[index - 1], history[index]])
        }
        var selected: [AssistantMessage] = []
        for pair in pairs.reversed().prefix(maximumHistoryMessages / 2) {
            let cost = pair.reduce(0) { $0 + estimatedTokens($1.content) }
            guard cost <= remaining else { break }
            remaining -= cost; selected.insert(contentsOf: pair, at: 0)
        }
        return [OpenRouterMessage(role: .system, content: system)] + selected.map {
            OpenRouterMessage(role: $0.role == .user ? .user : .assistant, content: $0.content)
        } + [OpenRouterMessage(role: .user, content: current)]
    }
}

public struct AssistantUsage: Codable, Equatable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cost: Double?
    public init?(payload: OpenRouterJSON) {
        guard case .object(let fields) = payload else { return nil }
        func number(_ key: String) -> Double? { if case .number(let n) = fields[key], n.isFinite, n >= 0 { return n }; return nil }
        guard let prompt = number("prompt_tokens"), let completion = number("completion_tokens"),
              prompt < Double(Int.max), completion < Double(Int.max) else { return nil }
        promptTokens = Int(prompt); completionTokens = Int(completion)
        totalTokens = Int(min(number("total_tokens") ?? (prompt + completion), Double(Int.max / 2)))
        cost = number("cost")
    }
}

public struct AssistantModelOption: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let contextLength: Int
    public let inputPrice: Double
    public let outputPrice: Double
    public var isFree: Bool { inputPrice == 0 && outputPrice == 0 }
    public init(id: String, name: String, contextLength: Int, inputPrice: Double, outputPrice: Double) {
        self.id = id; self.name = name; self.contextLength = contextLength; self.inputPrice = inputPrice; self.outputPrice = outputPrice
    }
    public static let recommendedIDs = ["google/gemma-4-26b-a4b-it:free", "google/gemma-4-31b-it:free", "nvidia/nemotron-3-super-120b-a12b:free", "openai/gpt-oss-20b", "openai/gpt-oss-120b", "qwen/qwen3-30b-a3b-instruct-2507", "meta-llama/llama-3.1-8b-instruct", "mistralai/mistral-nemo"]
    public static let initialOptions: [AssistantModelOption] = [
        .init(id: "google/gemma-4-26b-a4b-it:free", name: "Google: Gemma 4 26B A4B  (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0),
        .init(id: "google/gemma-4-31b-it:free", name: "Google: Gemma 4 31B (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0),
        .init(id: "nvidia/nemotron-3-super-120b-a12b:free", name: "NVIDIA: Nemotron 3 Super (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0),
        .init(id: "openai/gpt-oss-20b", name: "OpenAI: gpt-oss-20b", contextLength: 131072, inputPrice: 0.000000018, outputPrice: 0.00000009),
        .init(id: "openai/gpt-oss-120b", name: "OpenAI: gpt-oss-120b", contextLength: 131072, inputPrice: 0.000000037, outputPrice: 0.00000017),
        .init(id: "qwen/qwen3-30b-a3b-instruct-2507", name: "Qwen: Qwen3 30B A3B Instruct 2507", contextLength: 262144, inputPrice: 0.0000001, outputPrice: 0.0000003),
        .init(id: "meta-llama/llama-3.1-8b-instruct", name: "Meta: Llama 3.1 8B Instruct", contextLength: 131072, inputPrice: 0.00000005, outputPrice: 0.00000008),
        .init(id: "mistralai/mistral-nemo", name: "Mistral: Mistral Nemo", contextLength: 131072, inputPrice: 0.000000029, outputPrice: 0.00000003),
    ]
    public static func catalog(from data: Data) throws -> [AssistantModelOption] {
        struct Response: Decodable { let data: [Model] }
        struct Model: Decodable {
            let id: String; let name: String; let context_length: Int
            let pricing: Pricing; let architecture: Architecture
        }
        struct Pricing: Decodable { let prompt: String; let completion: String }
        struct Architecture: Decodable { let input_modalities: [String]; let output_modalities: [String] }
        return try JSONDecoder().decode(Response.self, from: data).data.compactMap { model in
            guard recommendedIDs.contains(model.id), model.architecture.input_modalities.contains("text"),
                  model.architecture.output_modalities.contains("text"),
                  let input = Double(model.pricing.prompt), let output = Double(model.pricing.completion),
                  input.isFinite, output.isFinite, input >= 0, output >= 0,
                  input <= 0.0000002, output <= 0.0000005, model.context_length >= 8192 else { return nil }
            return AssistantModelOption(id: model.id, name: model.name, contextLength: model.context_length, inputPrice: input, outputPrice: output)
        }.sorted {
            if $0.inputPrice + $0.outputPrice == $1.inputPrice + $1.outputPrice { return $0.id < $1.id }
            if $0.isFree != $1.isFree { return $0.isFree }
            return $0.inputPrice + $0.outputPrice < $1.inputPrice + $1.outputPrice
        }
    }
}

public enum AssistantRetryPolicy {
    public static func shouldTryAnotherFreeModel(after error: Error) -> Bool {
        switch error {
        case OpenRouterError.http(let status, _): return [429, 502, 503].contains(status)
        case OpenRouterError.api(let code, _): return code == .number(429) || code == .string("429")
        default: return false
        }
    }
}
