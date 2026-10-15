import Foundation
import XCTest
@testable import WorkdayCore

final class OpenRouterTests: XCTestCase {
    private let client = OpenRouterClient(configuration: .init(apiKey: "test-key", appTitle: "Test"))

    func testRequestAndExtensionFields() throws {
        let request = OpenRouterRequest(model: "test/model", messages: [.init(role: .user, content: "你好")],
                                        temperature: 0.5, maxTokens: 100,
                                        additionalParameters: ["stream": .bool(false), "provider": .object(["order": .array([.string("test")])])])
        let http = try client.makeURLRequest(request)
        XCTAssertEqual(http.httpMethod, "POST")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-OpenRouter-Title"), "Test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        XCTAssertNotNil(body["provider"])
    }

    func testSSEFramingAcrossBytes() throws {
        var parser = SSEParser(maximumEventBytes: 1024)
        var events: [String] = []
        let wire = "\u{FEFF}: heartbeat\r\ndata: 你好\r\ndata: world\r\n\r\nevent: message\ndata: [DONE]\n\n"
        for byte in wire.utf8 {
            if let event = try parser.append(byte) { events.append(event) }
        }
        XCTAssertEqual(events, ["你好\nworld", "[DONE]"])
    }

    func testOversizedEventFails() throws {
        var parser = SSEParser(maximumEventBytes: 8)
        XCTAssertThrowsError(try Array("data: too long".utf8).forEach { _ = try parser.append($0) })
    }

    func testChunkPreservesReasoningToolsUsageAndUnknownFields() throws {
        let chunk = try client.decodeEvent(#"{"id":"g1","choices":[{"index":0,"delta":{"content":"你好","reasoning":"思考","tool_calls":[{"index":0,"function":{"arguments":"{}"}}]},"finish_reason":null}],"usage":{"total_tokens":10},"provider":"test"}"#)
        XCTAssertEqual(chunk.choices.first?.delta?.content, "你好")
        XCTAssertEqual(chunk.choices.first?.delta?.reasoning, "思考")
        XCTAssertEqual(chunk.choices.first?.delta?.toolCalls?.count, 1)
        XCTAssertEqual(chunk.usage, .object(["total_tokens": .number(10)]))
        if case .object(let fields) = chunk.raw { XCTAssertEqual(fields["provider"], .string("test")) }
        else { XCTFail("Missing raw payload") }
        let usage = try client.decodeEvent(#"{"choices":[],"usage":{"total_tokens":10}}"#)
        XCTAssertTrue(usage.choices.isEmpty)
    }

    func testMidstreamErrorAndInvalidJSONFail() {
        XCTAssertThrowsError(try client.decodeEvent(#"{"error":{"code":"server_error","message":"disconnected"},"choices":[]}"#)) { error in
            guard case OpenRouterError.api(let code, let message) = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(code, .string("server_error"))
            XCTAssertEqual(message, "disconnected")
        }
        XCTAssertThrowsError(try client.decodeEvent("invalid json"))
    }

    func testStreamFinishesOnlyAfterDone() async throws {
        let chunks = try await collect(path: "success")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks.first?.choices.first?.delta?.content, "你好")
        XCTAssertNotNil(chunks.last?.usage)
    }

    func testTruncatedStreamFails() async {
        do { _ = try await collect(path: "truncated"); XCTFail("Expected incomplete stream") }
        catch { guard case OpenRouterError.incompleteStream = error else { return XCTFail("\(error)") } }
    }

    func testHTTPFailure() async {
        do { _ = try await collect(path: "unauthorized"); XCTFail("Expected HTTP failure") }
        catch {
            guard case OpenRouterError.http(let status, let body) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("Invalid key"))
        }
    }

    func testWrongContentTypeAndStreamError() async {
        for path in ["json", "error"] {
            do { _ = try await collect(path: path); XCTFail("Expected failure") }
            catch {
                switch (path, error) {
                case ("json", OpenRouterError.unexpectedContentType): break
                case ("error", OpenRouterError.api): break
                default: XCTFail("\(error)")
                }
            }
        }
    }

    func testConsumerCancellationClosesConnection() async throws {
        let stopped = expectation(forNotification: Notification.Name("OpenRouterMockStopped"), object: nil) {
            ($0.object as? String) == "waiting"
        }
        let task = Task { try await collect(path: "waiting") }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        // AsyncThrowingStream can finish normally when its consumer is cancelled.
        _ = try? await task.value
        await fulfillment(of: [stopped], timeout: 2)
    }

    private func collect(path: String) async throws -> [OpenRouterChunk] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOpenRouterProtocol.self]
        let client = OpenRouterClient(configuration: .init(apiKey: "test", endpoint: URL(string: "https://example.test/\(path)")!))
        var chunks: [OpenRouterChunk] = []
        for try await chunk in client.stream(.init(model: "test", messages: [.init(role: .user, content: "Hello")]), sessionConfiguration: configuration) {
            chunks.append(chunk)
        }
        return chunks
    }
}

private final class MockOpenRouterProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let status = path == "unauthorized" ? 401 : 200
        let type = ["json", "unauthorized"].contains(path) ? "application/json" : "text/event-stream"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "waiting" { return }
        let body: String
        switch path {
        case "unauthorized": body = #"{"error":{"message":"Invalid key"}}"#
        case "json": body = "{}"
        case "error": body = "data: {\"error\":{\"code\":500,\"message\":\"Failed\"}}\n\n"
        default:
            body = ": processing\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好\"}}]}\n\ndata: {\"choices\":[],\"usage\":{\"total_tokens\":3}}\n\n" + (path == "success" ? "data: [DONE]\n\n" : "")
        }
        // Deliberately split UTF-8 and SSE fields into individual network bytes.
        for byte in body.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        NotificationCenter.default.post(name: Notification.Name("OpenRouterMockStopped"), object: request.url?.lastPathComponent)
    }
}
