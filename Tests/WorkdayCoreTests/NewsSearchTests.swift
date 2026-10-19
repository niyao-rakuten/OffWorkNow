import XCTest
@testable import WorkdayCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class NewsSearchTests: XCTestCase {
    func testNaturalLanguageSearchPreservesTopic() {
        for input in ["搜索中东石油战争的相关新闻", "帮我搜索关于中东石油战争的新闻", "查找中东石油战争相关报道", "查一下中东石油战争相关的新闻", "新闻搜索：中东石油战争", "搜索新闻：中东石油战争"] {
            XCTAssertEqual(BotInformationRequest.interpret(input), .searchNews("中东石油战争"), input)
            XCTAssertEqual(AIBot().interpret(input, now: Date()), .information(.searchNews("中东石油战争")))
        }
        XCTAssertEqual(BotInformationRequest.interpret("Search news about US oil & gas"), .searchNews("US oil & gas"))
        XCTAssertEqual(BotInformationRequest.interpret("搜索新闻"), .searchNews(""))
        XCTAssertNil(BotInformationRequest.interpret("提醒我14:00搜索中东相关新闻"))
        XCTAssertNil(BotInformationRequest.interpret("解释如何搜索新闻"))
        XCTAssertNil(BotInformationRequest.interpret("搜索 Swift 文档"))
    }
    func testQueryEncodingAndEdition() throws {
        let topic = "US oil & gas + 中东?"
        let urls = BotInformationClient.newsSearchURLs(topic: topic)
        let google = try XCTUnwrap(URLComponents(url: urls[0], resolvingAgainstBaseURL: false))
        XCTAssertEqual(google.queryItems?.first(where: { $0.name == "q" })?.value, topic + " when:7d")
        let bing = try XCTUnwrap(URLComponents(url: urls[1], resolvingAgainstBaseURL: false))
        XCTAssertEqual(bing.queryItems?.first(where: { $0.name == "q" })?.value, topic)
        let english = URLComponents(url: BotInformationClient.newsSearchURLs(topic: "oil war")[0], resolvingAgainstBaseURL: false)
        XCTAssertEqual(english?.queryItems?.first(where: { $0.name == "hl" })?.value, "en-US")
    }
    func testSearchParsesPublisherAndBingArticleLink() throws {
        let items = try BotNewsParser.parse(Data(Self.xml.utf8))
        XCTAssertEqual(items.first?.title, "Oil report")
        XCTAssertEqual(items.first?.sourceName, "Test Media")
        XCTAssertEqual(items.first?.sourceURL?.absoluteString, "https://example.com")
        XCTAssertEqual(items[1].url.absoluteString, "https://example.org/story?a=1&b=2")
        XCTAssertEqual(items[1].sourceName, "Second Media")
        XCTAssertNil(items[1].sourceURL)
    }
    func testSearchPartialFailureGroupingAndDeduplication() async throws {
        let output = try await client().fetch(.searchNews("partial"), now: Self.now)
        for language in ["en", "zh-Hans"] {
            let text = try XCTUnwrap(output[language])
            XCTAssertEqual(text.components(separatedBy: "Oil report").count - 1, 1)
            XCTAssertTrue(text.contains("### Test Media"))
            XCTAssertFalse(text.contains("Old report"))
            XCTAssertFalse(text.contains("Future report"))
        }
        XCTAssertTrue(output["en"]!.contains("Some providers are unavailable: Bing News"))
    }
    func testNoResultsIsDifferentFromUnavailable() async throws {
        let empty = try await client().fetch(.searchNews("empty"), now: Self.now)
        XCTAssertTrue(empty["en"]!.contains("No matching reports"))
        let failed = try await client().fetch(.searchNews("offline"), now: Self.now)
        XCTAssertTrue(failed["en"]!.contains("providers are unavailable"))
        XCTAssertFalse(failed["en"]!.contains("No matching reports"))
    }
    func testEmptyAndOverlongTopicsStayLocal() async throws {
        let empty = try await client().fetch(.searchNews(""), now: Self.now)
        XCTAssertTrue(empty["en"]!.contains("Enter a news topic"))
        let long = try await client().fetch(.searchNews(String(repeating: "a", count: 201)), now: Self.now)
        XCTAssertTrue(long["en"]!.contains("200 characters"))
    }
    private func client() -> BotInformationClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NewsSearchProtocol.self]
        return BotInformationClient(session: URLSession(configuration: config))
    }
    static let now = Date(timeIntervalSince1970: 1792124000)
    static let xml = """
    <rss xmlns:News="urn:bing"><channel>
    <item><title>Oil report - Test Media</title><link>https://news.google.com/rss/articles/abc</link><pubDate>Fri, 16 Oct 2026 12:00:00 +0800</pubDate><source url="https://example.com">Test Media</source></item>
    <item><title>Other report</title><link>https://www.bing.com/news/apiclick.aspx?url=https%3A%2F%2Fexample.org%2Fstory%3Fa%3D1%26b%3D2</link><pubDate>Fri, 16 Oct 2026 11:00:00 +0800</pubDate><News:Source>Second Media</News:Source></item>
    <item><title>Oil report</title><link>https://example.com/duplicate</link><pubDate>Fri, 16 Oct 2026 10:00:00 +0800</pubDate><source>Test Media</source></item>
    <item><title>Old report</title><link>https://example.com/old</link><pubDate>Thu, 01 Oct 2026 10:00:00 +0800</pubDate><source>Test Media</source></item>
    <item><title>Future report</title><link>https://example.com/future</link><pubDate>Fri, 23 Oct 2026 10:00:00 +0800</pubDate><source>Test Media</source></item>
    </channel></rss>
    """
}
private final class NewsSearchProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value ?? ""
        let failed = query.contains("offline") || (query.contains("partial") && request.url!.host == "www.bing.com")
        let empty = query.contains("empty")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: failed ? 503 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((empty ? "<rss><channel/></rss>" : NewsSearchTests.xml).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
