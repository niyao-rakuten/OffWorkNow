import Foundation

public enum AssistantContext {
    public static let maximumHistoryMessages = 12
    public static let defaultInputBudget = 4096
    public static let defaultOutputTokens = 1024
    public static let maximumInputBudget = 131072
    public static let maximumOutputTokens = 16384
    public static let inputBudgetOptions = [4096, 8192, 16384, 32768, 65536, 131072]
    public static let outputTokenOptions = [1024, 2048, 4096, 8192, 16384]
    public static func limits(for model: AssistantModelOption, inputBudget: Int, outputTokens: Int) throws -> AssistantRequestLimits {
        guard inputBudget > 0, outputTokens > 0, model.effectiveContextLength >= 1024,
              model.maximumOutputTokens.map({ $0 > 0 }) ?? true else { throw ValidationError(L10n.text("模型的 token 限额无效，请刷新模型列表。")) }
        let input = min(inputBudget, maximumInputBudget)
        let available = model.effectiveContextLength - 512
        let reserveInput = min(input, defaultInputBudget, available - 1)
        let output = min(outputTokens, maximumOutputTokens, model.maximumOutputTokens ?? maximumOutputTokens, available - reserveInput)
        return AssistantRequestLimits(inputBudget: min(input, available - output), outputTokens: output)
    }
    /// UTF-8 bytes deliberately overestimate typical text tokens; include message framing overhead.
    public static func isConversationModel(_ id: String?) -> Bool {
        guard let id else { return true }
        let name = id.lowercased()
        return !["content-safety", "safeguard", "guard-", "moderation", "rerank", "embedding"].contains(where: name.contains)
    }
    public static func estimatedTokens(_ text: String) -> Int { text.utf8.count + 24 }
    public static func build(history: [AssistantMessage], system: String, current: String, proactive: Bool = false,
                             inputBudget: Int = defaultInputBudget, now: Date = Date(), calendar: Calendar = .current) throws -> [OpenRouterMessage] {
        var remaining = inputBudget - estimatedTokens(system) - estimatedTokens(current)
        guard remaining >= 0 else { throw ValidationError("消息过长，请缩短后再发送（本次上下文预算 \(inputBudget)）。") }
        if proactive {
            return [OpenRouterMessage(role: .system, content: system), OpenRouterMessage(role: .system, content: current)]
        }
        let history = AssistantTimeline.today(history, now: now, calendar: calendar)
        var pairs: [[AssistantMessage]] = []
        for index in history.indices where history[index].role == .assistant && history[index].complete && !history[index].content.isEmpty && isConversationModel(history[index].modelID) {
            if history[index].proactive == true { pairs.append([history[index]]); continue }
            guard index > 0, history[index - 1].role == .user, history[index - 1].complete else { continue }
            pairs.append([history[index - 1], history[index]])
        }
        var selected: [AssistantMessage] = []
        for pair in pairs.reversed().prefix(maximumHistoryMessages / 2) {
            let cost = pair.reduce(0) { $0 + estimatedTokens($1.contextContent) }
            guard cost <= remaining else { break }
            remaining -= cost; selected.insert(contentsOf: pair, at: 0)
        }
        return [OpenRouterMessage(role: .system, content: system)] + selected.map {
            OpenRouterMessage(role: $0.role == .user ? .user : .assistant, content: $0.contextContent)
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

public struct AssistantRequestLimits: Equatable, Sendable {
    public let inputBudget: Int
    public let outputTokens: Int
}

public struct AssistantModelOption: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let contextLength: Int
    public let inputPrice: Double
    public let outputPrice: Double
    public let providerContextLength: Int?
    public let maximumOutputTokens: Int?
    public let hasTieredPricing: Bool?
    public let canDisableReasoning: Bool?
    public let inputModalities: [String]?
    public let expirationDate: String?
    public var supportsImages: Bool { inputModalities?.contains("image") == true }
    public var isFree: Bool { inputPrice == 0 && outputPrice == 0 }
    public var effectiveContextLength: Int { min(contextLength, providerContextLength ?? contextLength) }
    /// Prefer a direct visible reply when the provider explicitly supports disabling optional thinking.
    public var chatParameters: [String: OpenRouterJSON] {
        canDisableReasoning == true ? ["reasoning": .object(["enabled": .bool(false)])] : [:]
    }
    public init(id: String, name: String, contextLength: Int, inputPrice: Double, outputPrice: Double,
                providerContextLength: Int? = nil, maximumOutputTokens: Int? = nil,
                hasTieredPricing: Bool? = nil, canDisableReasoning: Bool? = nil,
                inputModalities: [String]? = nil, expirationDate: String? = nil) {
        self.id = id; self.name = name; self.contextLength = contextLength; self.inputPrice = inputPrice; self.outputPrice = outputPrice
        self.providerContextLength = providerContextLength; self.maximumOutputTokens = maximumOutputTokens
        self.hasTieredPricing = hasTieredPricing; self.canDisableReasoning = canDisableReasoning
        self.inputModalities = inputModalities; self.expirationDate = expirationDate
    }
    public static var recommendedIDs: [String] { initialOptions.map(\.id) }
    public static let maximumInputPrice = 0.0000003
    public static let maximumOutputPrice = 0.000001
    // Official catalog snapshot: 2026-10-16. The refresh endpoint remains authoritative.
    public static let initialOptions: [AssistantModelOption] = [
        .init(id: "google/gemma-4-26b-a4b-it:free", name: "Google: Gemma 4 26B A4B  (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0, providerContextLength: 262144, maximumOutputTokens: 32768, canDisableReasoning: true, inputModalities: ["image", "text", "video"]),
        .init(id: "google/gemma-4-31b-it:free", name: "Google: Gemma 4 31B (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0, providerContextLength: 262144, maximumOutputTokens: 32768, canDisableReasoning: true, inputModalities: ["image", "text", "video"]),
        .init(id: "nvidia/nemotron-3-super-120b-a12b:free", name: "NVIDIA: Nemotron 3 Super (free)", contextLength: 262144, inputPrice: 0, outputPrice: 0, providerContextLength: 262144, maximumOutputTokens: 235929, canDisableReasoning: true, inputModalities: ["text"]),
        .init(id: "openai/gpt-oss-20b", name: "OpenAI: gpt-oss-20b", contextLength: 131072, inputPrice: 0.000000018, outputPrice: 0.00000009, providerContextLength: 131072, maximumOutputTokens: 32768, inputModalities: ["text"]),
        .init(id: "openai/gpt-oss-120b", name: "OpenAI: gpt-oss-120b", contextLength: 131072, inputPrice: 0.00000015, outputPrice: 0.0000006, providerContextLength: 131072, maximumOutputTokens: 65536, inputModalities: ["text"]),
        .init(id: "qwen/qwen3-30b-a3b-instruct-2507", name: "Qwen: Qwen3 30B A3B Instruct 2507", contextLength: 262144, inputPrice: 0.0000001, outputPrice: 0.0000003, providerContextLength: 262144, maximumOutputTokens: 235929, inputModalities: ["text"]),
        .init(id: "meta-llama/llama-3.1-8b-instruct", name: "Meta: Llama 3.1 8B Instruct", contextLength: 131072, inputPrice: 0.00000005, outputPrice: 0.00000008, providerContextLength: 131072, maximumOutputTokens: 117964, inputModalities: ["text"]),
        .init(id: "mistralai/mistral-nemo", name: "Mistral: Mistral Nemo", contextLength: 131072, inputPrice: 0.000000029, outputPrice: 0.00000003, providerContextLength: 131072, maximumOutputTokens: 16384, inputModalities: ["text"]),
        .init(id: "nvidia/nemotron-3.5-super-vl:free", name: "NVIDIA: Nemotron 3.5 Super VL (free)", contextLength: 1000000, inputPrice: 0, outputPrice: 0, providerContextLength: 1000000, maximumOutputTokens: 131072, canDisableReasoning: true, inputModalities: ["text", "image", "video"]),
        .init(id: "nvidia/nemotron-3.5-lightning:free", name: "NVIDIA: Nemotron 3.5 Lightning (free)", contextLength: 1000000, inputPrice: 0, outputPrice: 0, providerContextLength: 1000000, maximumOutputTokens: 65536, canDisableReasoning: true, inputModalities: ["text"]),
        .init(id: "deepseek/deepseek-v4-flash", name: "DeepSeek: DeepSeek V4 Flash 0423", contextLength: 1048576, inputPrice: 0.000000091, outputPrice: 0.000000182, providerContextLength: 1048575, maximumOutputTokens: 943717, canDisableReasoning: true, inputModalities: ["text"]),
        .init(id: "deepseek/deepseek-v4.1-flash", name: "DeepSeek: DeepSeek V4.1 Flash", contextLength: 1048576, inputPrice: 0.000000018, outputPrice: 0.000000684, providerContextLength: 1048576, maximumOutputTokens: 943718, canDisableReasoning: true, inputModalities: ["text", "image"]),
        .init(id: "deepseek/deepseek-v3.2", name: "DeepSeek: DeepSeek V3.2", contextLength: 163840, inputPrice: 0.000000259, outputPrice: 0.0000008, providerContextLength: 163840, maximumOutputTokens: 147456, canDisableReasoning: true, inputModalities: ["text"]),
        .init(id: "qwen/qwen3.7-flash", name: "Qwen: Qwen3.7 Flash", contextLength: 1000000, inputPrice: 0.00000003, outputPrice: 0.00000013, providerContextLength: 1000000, maximumOutputTokens: 65536, hasTieredPricing: true, canDisableReasoning: true, inputModalities: ["text", "image", "video"]),
        .init(id: "qwen/qwen3.8-flash", name: "Qwen: Qwen3.8 Flash", contextLength: 1000000, inputPrice: 0.00000015, outputPrice: 0.00000047, providerContextLength: 1000000, maximumOutputTokens: 131072, canDisableReasoning: true, inputModalities: ["text", "image", "video"]),
        .init(id: "qwen/qwen3.5-flash-02-23", name: "Qwen: Qwen3.5-Flash", contextLength: 1000000, inputPrice: 0.000000065, outputPrice: 0.00000026, providerContextLength: 1000000, maximumOutputTokens: 65536, canDisableReasoning: true, inputModalities: ["text", "image", "video"]),
        .init(id: "qwen/qwen3-32b", name: "Qwen: Qwen3 32B", contextLength: 131072, inputPrice: 0.00000008, outputPrice: 0.00000028, providerContextLength: 40960, maximumOutputTokens: 16384, canDisableReasoning: true, inputModalities: ["text"]),
        .init(id: "qwen/qwen3-235b-a22b-2507", name: "Qwen: Qwen3 235B A22B Instruct 2507", contextLength: 262144, inputPrice: 0.00000009, outputPrice: 0.00000055, providerContextLength: 262144, maximumOutputTokens: 16384, inputModalities: ["text"]),
        .init(id: "qwen/qwen3-coder-30b-a3b-instruct", name: "Qwen: Qwen3 Coder 30B A3B Instruct", contextLength: 262144, inputPrice: 0.00000007, outputPrice: 0.00000028, providerContextLength: 262144, maximumOutputTokens: 235929, inputModalities: ["text"]),
        .init(id: "dots-studio/dots-3-note-preview:free", name: "Dots Studio: Dots3-Note Preview (free)", contextLength: 512000, inputPrice: 0, outputPrice: 0, providerContextLength: 512000, maximumOutputTokens: 460800, canDisableReasoning: true, inputModalities: ["text", "image"], expirationDate: "2026-12-31"),
        .init(id: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", name: "NVIDIA: Nemotron 3 Nano Omni (free)", contextLength: 256000, inputPrice: 0, outputPrice: 0, providerContextLength: 256000, maximumOutputTokens: 65536, canDisableReasoning: true, inputModalities: ["text", "audio", "image", "video"]),
    ]
    private var isAffordable: Bool {
        inputPrice.isFinite && outputPrice.isFinite && inputPrice >= 0 && outputPrice >= 0
            && inputPrice <= Self.maximumInputPrice && outputPrice <= Self.maximumOutputPrice
            && effectiveContextLength >= 8192 && (maximumOutputTokens.map { $0 > 0 } ?? true)
    }
    /// Retain saved catalog metadata while making newly shipped models visible immediately.
    public static func restoring(_ saved: [AssistantModelOption]) -> [AssistantModelOption] {
        var models = Dictionary(uniqueKeysWithValues: initialOptions.map { ($0.id, $0) })
        for model in saved where recommendedIDs.contains(model.id) && model.isAffordable {
            let bundled = models[model.id]!
            models[model.id] = AssistantModelOption(id: model.id, name: model.name, contextLength: model.contextLength,
                inputPrice: model.inputPrice, outputPrice: model.outputPrice,
                providerContextLength: model.providerContextLength ?? bundled.providerContextLength,
                maximumOutputTokens: model.maximumOutputTokens ?? bundled.maximumOutputTokens,
                hasTieredPricing: model.hasTieredPricing ?? bundled.hasTieredPricing,
                canDisableReasoning: model.canDisableReasoning ?? bundled.canDisableReasoning,
                inputModalities: model.inputModalities ?? bundled.inputModalities,
                expirationDate: model.expirationDate ?? bundled.expirationDate)
        }
        return sorted(Array(models.values))
    }
    public static func catalog(from data: Data) throws -> [AssistantModelOption] {
        struct Response: Decodable { let data: [Model] }
        struct Model: Decodable {
            let id: String; let name: String; let context_length: Int
            let pricing: Pricing; let architecture: Architecture
            let top_provider: Provider?
            let supported_parameters: [String]?
            let reasoning: Reasoning?
            let expiration_date: String?
        }
        struct Provider: Decodable { let context_length: Int?; let max_completion_tokens: Int? }
        struct Reasoning: Decodable { let mandatory: Bool? }
        struct Pricing: Decodable { let prompt: String; let completion: String; let overrides: [OpenRouterJSON]? }
        struct Architecture: Decodable { let input_modalities: [String]; let output_modalities: [String] }
        let options: [AssistantModelOption] = try JSONDecoder().decode(Response.self, from: data).data.compactMap { model in
            guard recommendedIDs.contains(model.id), model.architecture.input_modalities.contains("text"),
                  model.architecture.output_modalities.contains("text"),
                  let input = Double(model.pricing.prompt), let output = Double(model.pricing.completion) else { return nil }
            let option = AssistantModelOption(id: model.id, name: model.name, contextLength: model.context_length,
                inputPrice: input, outputPrice: output, providerContextLength: model.top_provider?.context_length,
                maximumOutputTokens: model.top_provider?.max_completion_tokens,
                hasTieredPricing: model.pricing.overrides?.isEmpty == false,
                canDisableReasoning: model.reasoning?.mandatory == false && model.supported_parameters?.contains("reasoning") == true,
                inputModalities: model.architecture.input_modalities, expirationDate: model.expiration_date)
            return option.isAffordable ? option : nil
        }
        return sorted(options)
    }
    private static func sorted(_ models: [AssistantModelOption]) -> [AssistantModelOption] {
        models.sorted {
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
