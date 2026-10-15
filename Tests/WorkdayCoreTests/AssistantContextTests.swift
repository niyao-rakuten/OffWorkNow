import XCTest
@testable import WorkdayCore

final class AssistantContextTests: XCTestCase {
    func testProactiveReportUsesInternalContextWithoutUserMessage() throws {
        let result = try AssistantContext.build(history: [.init(role: .user, content: "old")],
            system: "pet", current: "checkout snapshot", proactive: true)
        XCTAssertEqual(contents(result), ["pet", "checkout snapshot"])
        XCTAssertTrue(result.allSatisfy { $0.role == .system })
    }
    func testFollowUpIncludesProactivePetReport() throws {
        let report = AssistantMessage(role: .assistant, content: "today report", proactive: true)
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.proactive, true)
        let result = try AssistantContext.build(history: [decoded], system: "pet", current: "explain report")
        XCTAssertEqual(contents(result), ["pet", "today report", "explain report"])
        XCTAssertEqual(result[1].role, .assistant)
    }
    private func contents(_ messages: [OpenRouterMessage]) -> [String] {
        messages.compactMap { if case .string(let text) = $0.content { return text }; return nil }
    }
    func testKeepsSixLatestCompleteTurnsAndCurrentInput() throws {
        var history: [AssistantMessage] = []
        for n in 0..<10 { history += [.init(role: .user, content: "u\(n)"), .init(role: .assistant, content: "a\(n)")] }
        let messages = try AssistantContext.build(history: history, system: "system", current: "new")
        XCTAssertEqual(messages.count, 14)
        XCTAssertEqual(contents(messages).first, "system")
        XCTAssertEqual(contents(messages)[1], "u4")
        XCTAssertEqual(contents(messages).last, "new")
    }
    func testBudgetDropsOldTurnsWithoutSplittingPair() throws {
        let history: [AssistantMessage] = [.init(role: .user, content: String(repeating: "x", count: 300)), .init(role: .assistant, content: "old"), .init(role: .user, content: "recent"), .init(role: .assistant, content: "reply")]
        let result = try AssistantContext.build(history: history, system: "s", current: "c", inputBudget: 140)
        XCTAssertEqual(contents(result), ["s", "recent", "reply", "c"])
        XCTAssertLessThanOrEqual(contents(result).reduce(0) { $0 + AssistantContext.estimatedTokens($1) }, 140)
    }
    func testSkipsInterruptedAndUnansweredTurns() throws {
        let history: [AssistantMessage] = [.init(role: .user, content: "failed"), .init(role: .assistant, content: "partial", complete: false), .init(role: .user, content: "unanswered")]
        XCTAssertEqual(contents(try AssistantContext.build(history: history, system: "s", current: "new")), ["s", "new"])
    }
    func testOversizedCurrentMessageRejectedWithoutTruncation() {
        XCTAssertThrowsError(try AssistantContext.build(history: [], system: "s", current: String(repeating: "你", count: 2000)))
    }
    func testUsageParsesZeroCostAndMissingCostDistinctly() {
        let base: [String: OpenRouterJSON] = ["prompt_tokens": .number(12), "completion_tokens": .number(8)]
        XCTAssertNil(AssistantUsage(payload: .object(base))?.cost)
        var free = base; free["cost"] = .number(0)
        XCTAssertEqual(AssistantUsage(payload: .object(free))?.cost, 0)
        XCTAssertEqual(AssistantUsage(payload: .object(free))?.totalTokens, 20)
        XCTAssertNil(AssistantUsage(payload: .null))
    }
    func testLegacyHistoryWithoutUsageStillLoads() throws {
        let message = AssistantMessage(role: .assistant, content: "old")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: data)
        XCTAssertNil(decoded.usage)
    }
    func testCatalogExcludesExpensiveAndNonTextModels() throws {
        let data = Data(#"{"data":[{"id":"google/gemma-4-31b-it:free","name":"Free","context_length":200000,"pricing":{"prompt":"0","completion":"0"},"architecture":{"input_modalities":["text"],"output_modalities":["text"]}},{"id":"openai/gpt-oss-20b","name":"Expensive","context_length":131072,"pricing":{"prompt":"0.01","completion":"0.01"},"architecture":{"input_modalities":["text"],"output_modalities":["text"]}},{"id":"mistralai/mistral-nemo","name":"Audio","context_length":131072,"pricing":{"prompt":"0","completion":"0"},"architecture":{"input_modalities":["text"],"output_modalities":["audio"]}}]}"#.utf8)
        XCTAssertEqual(try AssistantModelOption.catalog(from: data).map(\.id), ["google/gemma-4-31b-it:free"])
    }
    func testModerationRepliesDoNotPolluteConversationContext() throws {
        var reply = AssistantMessage(role: .assistant, content: "User Safety: safe")
        reply.modelID = "nvidia/nemotron-3.5-content-safety:free"
        let history = [AssistantMessage(role: .user, content: "介绍你自己"), reply]
        XCTAssertEqual(contents(try AssistantContext.build(history: history, system: "s", current: "你好")), ["s", "你好"])
        XCTAssertFalse(AssistantModelOption.recommendedIDs.contains("openrouter/free"))
    }

}
