import XCTest
@testable import WorkdayCore

final class AssistantCatalogTests: ChineseLocalizationTestCase {
    // Public model metadata fetched from OpenRouter on 2026-10-16, no account data.
    private static let fixture = Data(#"""
    {"data":[
    {"id":"google/gemma-4-26b-a4b-it:free","name":"Google: Gemma 4 26B A4B  (free)","context_length":262144,"architecture":{"modality":"text+image+video->text","input_modalities":["image","text","video"],"output_modalities":["text"],"tokenizer":"Gemma","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":262144,"max_completion_tokens":32768,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","response_format","seed","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":false}},
    {"id":"google/gemma-4-31b-it:free","name":"Google: Gemma 4 31B (free)","context_length":262144,"architecture":{"modality":"text+image+video->text","input_modalities":["image","text","video"],"output_modalities":["text"],"tokenizer":"Gemma","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":262144,"max_completion_tokens":32768,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","response_format","seed","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":false}},
    {"id":"nvidia/nemotron-3-super-120b-a12b:free","name":"NVIDIA: Nemotron 3 Super (free)","context_length":262144,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Other","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":262144,"max_completion_tokens":235929,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","reasoning_effort","response_format","seed","structured_outputs","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":true,"supports_max_tokens":true,"supported_efforts":["medium","low","none"],"default_effort":"medium"}},
    {"id":"openai/gpt-oss-20b","name":"OpenAI: gpt-oss-20b","context_length":131072,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"GPT","instruct_type":null},"pricing":{"prompt":"0.000000018","completion":"0.00000009","input_cache_read":"0.000000009"},"top_provider":{"context_length":131072,"max_completion_tokens":32768,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_tokens","min_p","presence_penalty","reasoning","reasoning_effort","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":true,"supported_efforts":["high","medium","low"],"default_effort":"medium"}},
    {"id":"openai/gpt-oss-120b","name":"OpenAI: gpt-oss-120b","context_length":131072,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"GPT","instruct_type":null},"pricing":{"prompt":"0.00000015","completion":"0.0000006","input_cache_read":"0.000000075"},"top_provider":{"context_length":131072,"max_completion_tokens":65536,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_tokens","min_p","presence_penalty","reasoning","reasoning_effort","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_a","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":true,"supported_efforts":["high","medium","low"],"default_effort":"medium"}},
    {"id":"qwen/qwen3-30b-a3b-instruct-2507","name":"Qwen: Qwen3 30B A3B Instruct 2507","context_length":262144,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Qwen3","instruct_type":null},"pricing":{"prompt":"0.0000001","completion":"0.0000003"},"top_provider":{"context_length":262144,"max_completion_tokens":235929,"is_moderated":false},"supported_parameters":["frequency_penalty","logit_bias","logprobs","max_tokens","presence_penalty","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null},
    {"id":"meta-llama/llama-3.1-8b-instruct","name":"Meta: Llama 3.1 8B Instruct","context_length":131072,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Llama3","instruct_type":"llama3"},"pricing":{"prompt":"0.00000005","completion":"0.00000008","input_cache_read":"0.000000025"},"top_provider":{"context_length":131072,"max_completion_tokens":117964,"is_moderated":false},"supported_parameters":["frequency_penalty","logit_bias","logprobs","max_tokens","min_p","presence_penalty","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null},
    {"id":"mistralai/mistral-nemo","name":"Mistral: Mistral Nemo","context_length":131072,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Mistral","instruct_type":null},"pricing":{"prompt":"0.000000029","completion":"0.00000003"},"top_provider":{"context_length":131072,"max_completion_tokens":16384,"is_moderated":false},"supported_parameters":["frequency_penalty","logit_bias","logprobs","max_tokens","min_p","presence_penalty","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null},
    {"id":"nvidia/nemotron-3.5-super-vl:free","name":"NVIDIA: Nemotron 3.5 Super VL (free)","context_length":1000000,"architecture":{"modality":"text+image+video->text","input_modalities":["text","image","video"],"output_modalities":["text"],"tokenizer":"Other","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":1000000,"max_completion_tokens":131072,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","response_format","seed","structured_outputs","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false}},
    {"id":"nvidia/nemotron-3.5-lightning:free","name":"NVIDIA: Nemotron 3.5 Lightning (free)","context_length":1000000,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Other","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":1000000,"max_completion_tokens":65536,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","seed","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false}},
    {"id":"deepseek/deepseek-v4-flash","name":"DeepSeek: DeepSeek V4 Flash 0423","context_length":1048576,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"DeepSeek","instruct_type":null},"pricing":{"prompt":"0.000000091","completion":"0.000000182","input_cache_read":"0.0000000182"},"top_provider":{"context_length":1048575,"max_completion_tokens":943717,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_completion_tokens","max_tokens","min_p","presence_penalty","reasoning","reasoning_effort","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_a","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"supported_efforts":["xhigh","high","none"],"default_effort":"high"}},
    {"id":"deepseek/deepseek-v4.1-flash","name":"DeepSeek: DeepSeek V4.1 Flash","context_length":1048576,"architecture":{"modality":"text+image->text","input_modalities":["text","image"],"output_modalities":["text"],"tokenizer":"DeepSeek","instruct_type":null},"pricing":{"prompt":"0.000000018","completion":"0.000000684","input_cache_read":"0.0000000054"},"top_provider":{"context_length":1048576,"max_completion_tokens":943718,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_tokens","min_p","presence_penalty","reasoning","reasoning_effort","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":true,"supported_efforts":["max","high","low","none"],"default_effort":"high"}},
    {"id":"deepseek/deepseek-v3.2","name":"DeepSeek: DeepSeek V3.2","context_length":163840,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"DeepSeek","instruct_type":null},"pricing":{"prompt":"0.000000259","completion":"0.0000008","input_cache_read":"0.00000014"},"top_provider":{"context_length":163840,"max_completion_tokens":147456,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_tokens","min_p","presence_penalty","reasoning","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":false}},
    {"id":"qwen/qwen3.7-flash","name":"Qwen: Qwen3.7 Flash","context_length":1000000,"architecture":{"modality":"text+image+video->text","input_modalities":["text","image","video"],"output_modalities":["text"],"tokenizer":"Qwen","instruct_type":null},"pricing":{"prompt":"0.00000003","completion":"0.00000013","input_cache_read":"0.000000006","input_cache_write":"0.000000038","overrides":[{"min_prompt_tokens":32000,"prompt":"0.0000001","completion":"0.0000004","input_cache_read":"0.00000002","input_cache_write":"0.000000125"},{"min_prompt_tokens":256000,"prompt":"0.0000002","completion":"0.0000008","input_cache_read":"0.00000004","input_cache_write":"0.00000025"}]},"top_provider":{"context_length":1000000,"max_completion_tokens":65536,"is_moderated":false},"supported_parameters":["include_reasoning","logprobs","max_tokens","presence_penalty","reasoning","response_format","seed","temperature","tool_choice","tools","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":true,"supports_max_tokens":true}},
    {"id":"qwen/qwen3.8-flash","name":"Qwen: Qwen3.8 Flash","context_length":1000000,"architecture":{"modality":"text+image+video->text","input_modalities":["text","image","video"],"output_modalities":["text"],"tokenizer":"Qwen","instruct_type":null},"pricing":{"prompt":"0.00000015","completion":"0.00000047","input_cache_read":"0.000000016"},"top_provider":{"context_length":1000000,"max_completion_tokens":131072,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logprobs","max_tokens","presence_penalty","reasoning","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":true,"supports_max_tokens":true}},
    {"id":"qwen/qwen3.5-flash-02-23","name":"Qwen: Qwen3.5-Flash","context_length":1000000,"architecture":{"modality":"text+image+video->text","input_modalities":["text","image","video"],"output_modalities":["text"],"tokenizer":"Qwen3","instruct_type":null},"pricing":{"prompt":"0.000000065","completion":"0.00000026"},"top_provider":{"context_length":1000000,"max_completion_tokens":65536,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","max_tokens","presence_penalty","reasoning","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_p"],"expiration_date":null,"reasoning":{"mandatory":false}},
    {"id":"qwen/qwen3-32b","name":"Qwen: Qwen3 32B","context_length":131072,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Qwen3","instruct_type":"qwen3"},"pricing":{"prompt":"0.00000008","completion":"0.00000028"},"top_provider":{"context_length":40960,"max_completion_tokens":16384,"is_moderated":false},"supported_parameters":["frequency_penalty","include_reasoning","logit_bias","logprobs","max_tokens","min_p","presence_penalty","reasoning","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_a","top_k","top_logprobs","top_p"],"expiration_date":null,"reasoning":{"mandatory":false}},
    {"id":"qwen/qwen3-235b-a22b-2507","name":"Qwen: Qwen3 235B A22B Instruct 2507","context_length":262144,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Qwen3","instruct_type":null},"pricing":{"prompt":"0.00000009","completion":"0.00000055"},"top_provider":{"context_length":262144,"max_completion_tokens":16384,"is_moderated":false},"supported_parameters":["frequency_penalty","logit_bias","logprobs","max_tokens","min_p","presence_penalty","repetition_penalty","response_format","seed","stop","structured_outputs","temperature","tool_choice","tools","top_k","top_logprobs","top_p"],"expiration_date":null},
    {"id":"qwen/qwen3-coder-30b-a3b-instruct","name":"Qwen: Qwen3 Coder 30B A3B Instruct","context_length":262144,"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"],"tokenizer":"Qwen3","instruct_type":null},"pricing":{"prompt":"0.00000007","completion":"0.00000028"},"top_provider":{"context_length":262144,"max_completion_tokens":235929,"is_moderated":false},"supported_parameters":["frequency_penalty","max_tokens","response_format","structured_outputs","temperature","tool_choice","tools","top_k","top_p"],"expiration_date":null},
    {"id":"dots-studio/dots-3-note-preview:free","name":"Dots Studio: Dots3-Note Preview (free)","context_length":512000,"architecture":{"modality":"text+image->text","input_modalities":["text","image"],"output_modalities":["text"],"tokenizer":"Other","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":512000,"max_completion_tokens":460800,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","response_format","structured_outputs","temperature","tool_choice","tools","top_p"],"expiration_date":"2026-12-31","reasoning":{"mandatory":false}},
    {"id":"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free","name":"NVIDIA: Nemotron 3 Nano Omni (free)","context_length":256000,"architecture":{"modality":"text+image+audio+video->text","input_modalities":["text","audio","image","video"],"output_modalities":["text"],"tokenizer":"Other","instruct_type":null},"pricing":{"prompt":"0","completion":"0"},"top_provider":{"context_length":256000,"max_completion_tokens":65536,"is_moderated":false},"supported_parameters":["include_reasoning","max_tokens","reasoning","seed","temperature","tool_choice","tools","top_p"],"expiration_date":null,"reasoning":{"mandatory":false,"default_enabled":true,"supports_max_tokens":true}}
    ]}
    """#.utf8)
    func testVisionMetadataSurvivesRefreshAndLegacyCacheRestore() throws {
        let catalog = try AssistantModelOption.catalog(from: Self.fixture)
        let preview = try XCTUnwrap(catalog.first { $0.id == "dots-studio/dots-3-note-preview:free" })
        XCTAssertTrue(preview.isFree)
        XCTAssertTrue(preview.supportsImages)
        XCTAssertEqual(preview.expirationDate, "2026-12-31")
        let legacy = AssistantModelOption(id: preview.id, name: preview.name, contextLength: preview.contextLength, inputPrice: 0, outputPrice: 0)
        let decoded = try JSONDecoder().decode(AssistantModelOption.self, from: JSONEncoder().encode(legacy))
        let restored = try XCTUnwrap(AssistantModelOption.restoring([decoded]).first { $0.id == preview.id })
        XCTAssertTrue(restored.supportsImages)
        XCTAssertEqual(restored.expirationDate, preview.expirationDate)
        XCTAssertTrue(catalog.contains { $0.id == "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free" && $0.supportsImages && $0.isFree })
    }
    func testVerifiedCatalogIncludesDeepSeekQwenAndLongContextFreeOptions() throws {
        let catalog = try AssistantModelOption.catalog(from: Self.fixture)
        XCTAssertEqual(Set(catalog.map(\.id)), Set(AssistantModelOption.recommendedIDs))
        XCTAssertEqual(catalog.filter { $0.id.hasPrefix("deepseek/") }.count, 3)
        XCTAssertTrue(catalog.contains { $0.id == "qwen/qwen3.7-flash" && $0.contextLength == 1_000_000 })
        XCTAssertTrue(catalog.contains { $0.isFree && $0.contextLength == 1_000_000 })
        XCTAssertEqual(catalog.count, 21)
        let qwen = try XCTUnwrap(catalog.first { $0.id == "qwen/qwen3.7-flash" })
        XCTAssertEqual(qwen.inputPrice * 1_000_000, 0.03, accuracy: 0.000001)
        XCTAssertEqual(qwen.outputPrice * 1_000_000, 0.13, accuracy: 0.000001)
        XCTAssertEqual(qwen.hasTieredPricing, true)
        let firstPaid = try XCTUnwrap(catalog.firstIndex { !$0.isFree })
        XCTAssertTrue(catalog.prefix(firstPaid).allSatisfy(\.isFree))
        XCTAssertFalse(catalog.suffix(from: firstPaid).contains(where: \.isFree))
    }
    func testLegacyCacheRestoresNewChoicesAndProviderLimitsWithoutDuplicates() throws {
        let legacy = Data(#"{"id":"qwen/qwen3-30b-a3b-instruct-2507","name":"Saved Qwen","contextLength":262144,"inputPrice":0.0000001,"outputPrice":0.0000003}"#.utf8)
        let saved = try JSONDecoder().decode(AssistantModelOption.self, from: legacy)
        XCTAssertNil(saved.maximumOutputTokens)
        let restored = AssistantModelOption.restoring([saved, saved])
        XCTAssertEqual(restored.count, AssistantModelOption.recommendedIDs.count)
        let original = try XCTUnwrap(restored.first { $0.id == saved.id })
        XCTAssertEqual(original.name, "Saved Qwen")
        XCTAssertNotNil(original.maximumOutputTokens)
        XCTAssertTrue(restored.contains { $0.id == "deepseek/deepseek-v4.1-flash" })
        XCTAssertFalse(restored.contains { $0.id == "openrouter/free" })
    }
    func testRequestLimitsHonorContextProviderOutputAndUserBudget() throws {
        for model in try AssistantModelOption.catalog(from: Self.fixture) {
            let limits = try AssistantContext.limits(for: model, inputBudget: 131072, outputTokens: 16384)
            XCTAssertLessThanOrEqual(limits.inputBudget + limits.outputTokens + 512, model.effectiveContextLength)
            XCTAssertLessThanOrEqual(limits.outputTokens, model.maximumOutputTokens ?? 16384)
            XCTAssertGreaterThan(limits.inputBudget, 0)
            XCTAssertGreaterThan(limits.outputTokens, 0)
        }
        let model = AssistantModelOption(id: "test", name: "test", contextLength: 131072, inputPrice: 0, outputPrice: 0,
            providerContextLength: 8192, maximumOutputTokens: 2048)
        let limited = try AssistantContext.limits(for: model, inputBudget: 131072, outputTokens: 16384)
        XCTAssertEqual(limited.outputTokens, 2048)
        XCTAssertEqual(limited.inputBudget, 5632)
        XCTAssertThrowsError(try AssistantContext.limits(for: model, inputBudget: 0, outputTokens: 1024))
    }
    func testLargerUserBudgetActuallyAllowsLongerMessages() throws {
        let model = try XCTUnwrap(AssistantModelOption.initialOptions.first { $0.id == "qwen/qwen3.7-flash" })
        let message = String(repeating: "你好", count: 1000)
        XCTAssertThrowsError(try AssistantContext.build(history: [], system: "system", current: message))
        let limits = try AssistantContext.limits(for: model, inputBudget: 32768, outputTokens: 8192)
        let context = try AssistantContext.build(history: [], system: "system", current: message, inputBudget: limits.inputBudget)
        XCTAssertEqual(context.count, 2)
        let request = OpenRouterRequest(model: model.id, messages: context, maxTokens: limits.outputTokens, additionalParameters: model.chatParameters)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["max_tokens"] as? Int, 8192)
        XCTAssertEqual((json["reasoning"] as? [String: Any])?["enabled"] as? Bool, false)
    }
    func testReasoningIsDisabledOnlyWhenModelExplicitlyAllowsIt() throws {
        let catalog = try AssistantModelOption.catalog(from: Self.fixture)
        let deepseek = try XCTUnwrap(catalog.first { $0.id == "deepseek/deepseek-v4.1-flash" })
        XCTAssertEqual(deepseek.chatParameters["reasoning"], .object(["enabled": .bool(false)]))
        let coder = try XCTUnwrap(catalog.first { $0.id == "qwen/qwen3-coder-30b-a3b-instruct" })
        XCTAssertTrue(coder.chatParameters.isEmpty)
        var row = try firstRow()
        row["reasoning"] = ["mandatory": true]
        row["supported_parameters"] = ["reasoning"]
        let mandatory = try XCTUnwrap(AssistantModelOption.catalog(from: data(row)).first)
        XCTAssertTrue(mandatory.chatParameters.isEmpty)
    }
    func testLiveRefreshFiltersPriceRisesMissingModalitiesAndInvalidCapacity() throws {
        let original = try firstRow()
        for change: [String: Any] in [
            ["pricing": ["prompt": "0.00000031", "completion": "0"]],
            ["pricing": ["prompt": "0", "completion": "0.0000011"]],
            ["pricing": ["prompt": "NaN", "completion": "0"]],
            ["top_provider": ["context_length": 4096, "max_completion_tokens": 1024]],
            ["top_provider": ["context_length": 262144, "max_completion_tokens": 0]],
            ["architecture": ["input_modalities": ["image"], "output_modalities": ["text"]]],
            ["id": "deepseek/unverified-model:free"]
        ] {
            var row = original; row.merge(change) { _, new in new }
            XCTAssertTrue(try AssistantModelOption.catalog(from: data(row)).isEmpty)
        }
    }
    private func firstRow() throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.fixture) as? [String: Any])
        return try XCTUnwrap((object["data"] as? [[String: Any]])?.first)
    }
    private func data(_ row: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": [row]])
    }
}
