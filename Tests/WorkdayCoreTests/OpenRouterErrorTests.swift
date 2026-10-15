import XCTest
@testable import WorkdayCore

final class OpenRouterErrorTests: XCTestCase {
    func testHTTPErrorExplainsRateLimitAndAuthentication() {
        let limited = OpenRouterError.http(statusCode: 429, body: #"{"error":{"message":"Provider returned error"}}"#).localizedDescription
        XCTAssertTrue(limited.contains("429"))
        XCTAssertTrue(limited.contains("限流"))
        XCTAssertTrue(limited.contains("Provider returned error"))
        XCTAssertTrue(OpenRouterError.http(statusCode: 401, body: "").localizedDescription.contains("API Key"))
    }
    func testMalformedResponseBodyDoesNotLeakHTMLIntoUI() {
        let description = OpenRouterError.http(statusCode: 502, body: "<html>proxy error</html>").localizedDescription
        XCTAssertTrue(description.contains("502"))
        XCTAssertFalse(description.contains("<html>"))
    }
    func testRetryOnlyForTemporaryFailures() {
        for status in [429, 502, 503] {
            XCTAssertTrue(AssistantRetryPolicy.shouldTryAnotherFreeModel(after: OpenRouterError.http(statusCode: status, body: "")))
        }
        for status in [400, 401, 402, 403, 404] {
            XCTAssertFalse(AssistantRetryPolicy.shouldTryAnotherFreeModel(after: OpenRouterError.http(statusCode: status, body: "")))
        }
        XCTAssertFalse(AssistantRetryPolicy.shouldTryAnotherFreeModel(after: CancellationError()))
        XCTAssertFalse(AssistantRetryPolicy.shouldTryAnotherFreeModel(after: OpenRouterError.incompleteStream))
    }
}
