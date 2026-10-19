import XCTest
@testable import WorkdayCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BotInformationTests: XCTestCase {
    func testLocalRoutingDoesNotCaptureUnrelatedQuestions() {
        let bot = AIBot()
        for text in ["新闻", "今日新闻", "经济新闻", "政治新闻", "news", "黄金走势", "BTC走势", "股市走势", "A股走势", "日经走势", "纳指", "道指", "市场行情"] {
            guard case .information = bot.interpret(text, now: Date()) else { return XCTFail(text) }
        }
        XCTAssertNil(BotInformationRequest.interpret("解释一下新闻传播理论"))
        XCTAssertNil(BotInformationRequest.interpret("提醒我14:00看新闻"))
        XCTAssertEqual(BotInformationRequest.interpret(" BTC走势？ "), .markets(.bitcoin))
    }
    func testRSSCDATAAndInvalidLinks() throws {
        let xml = """
        <rss><channel>
        <item><title><![CDATA[A & B]]></title><link>https://example.com/a</link><pubDate>Fri, 16 Oct 2026 12:00:00 +0800</pubDate></item>
        <item><title>Unsafe</title><link>javascript:alert(1)</link><pubDate>Fri, 16 Oct 2026 12:00:00 +0800</pubDate></item>
        <item><title>Undated</title><link>https://example.com/b</link></item>
        </channel></rss>
        """
        let items = try BotNewsParser.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "A & B")
        XCTAssertEqual(items.first?.date.timeIntervalSince1970, 1792123200)
        XCTAssertThrowsError(try BotNewsParser.parse(Data("<html>broken".utf8)))
    }
    func testChartUsesDailyBaselineInsteadOfRangePreviousClose() throws {
        let quote = try BotMarketQuote.decode(Self.chart(), now: Date(timeIntervalSince1970: 1792124000))
        XCTAssertEqual(quote.previousClose, 100)
        XCTAssertEqual(quote.changePercent ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(quote.monthPercent ?? 0, 37.5, accuracy: 0.0001)
        XCTAssertEqual(quote.closes, [80, 100, 110])
        XCTAssertThrowsError(try BotMarketQuote.decode(Self.chart(price: -1)))
        XCTAssertThrowsError(try BotMarketQuote.decode(Self.chart(), now: .distantPast))
        XCTAssertThrowsError(try BotMarketQuote.decode(Data(#"{"chart":{"result":null}}"#.utf8)))
    }
    func testMarketPartialFailureHasBilingualResultsAndTimes() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InformationURLProtocol.self]
        let client = BotInformationClient(session: URLSession(configuration: config))
        let output = try await client.fetch(.markets(.stocks), now: Date(timeIntervalSince1970: 1792124000))
        XCTAssertTrue(output["zh-Hans"]?.contains("纳斯达克") == true)
        XCTAssertTrue(output["en"]?.contains("Nasdaq") == true)
        XCTAssertTrue(output["en"]?.contains("Quote time:") == true)
        XCTAssertTrue(output["en"]?.contains("Data unavailable") == true)
        XCTAssertFalse(output["en"]?.contains("Bitcoin / USD") == true)
    }
    func testNewsFiltersOldItemsAndDeduplicatesAcrossSources() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [InformationURLProtocol.self]
        let output = try await BotInformationClient(session: URLSession(configuration: config))
            .fetch(.news(.headlines), now: Date(timeIntervalSince1970: 1792124000))
        for language in ["zh-Hans", "en"] {
            let text = try XCTUnwrap(output[language])
            XCTAssertEqual(text.components(separatedBy: "Fresh headline").count - 1, 1)
            XCTAssertFalse(text.contains("Old headline"))
            XCTAssertFalse(text.contains("Future headline"))
            XCTAssertTrue(text.contains("https://example.com/fresh"))
        }
        XCTAssertTrue(output["en"]!.contains("Source temporarily unavailable"))
    }
    func testMissingCurrentCandleKeepsLastPriorDayAsBaseline() throws {
        let data = String(data: Self.chart(), encoding: .utf8)!.replacingOccurrences(of: "[80,null,100,110]", with: "[80,null,100,null]")
        let quote = try BotMarketQuote.decode(Data(data.utf8), now: Date(timeIntervalSince1970: 1792124000))
        XCTAssertEqual(quote.previousClose, 100)
    }
    func testCancelledFetchDoesNotReturnSuccessDigest() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [InformationURLProtocol.self]
        let task = Task {
            try Task.checkCancellation()
            return try await BotInformationClient(session: URLSession(configuration: config)).fetch(.markets(.gold))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled query succeeded") } catch { }
    }
    static func chart(price: Int = 110) -> Data {
        Data("""
        {"chart":{"result":[{"meta":{"regularMarketPrice":\(price),"regularMarketTime":1792123200,"chartPreviousClose":70,"currency":"USD","exchangeTimezoneName":"UTC"},"timestamp":[1791864000,1791950400,1792036800,1792123200],"indicators":{"quote":[{"close":[80,null,100,110]}]}}]}}
        """.utf8)
    }
}
private final class InformationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isRSS = request.url!.host != "query1.finance.yahoo.com"
        let success = request.url!.path.contains("IXIC") || (isRSS && request.url!.host != "feeds.bbci.co.uk")
        let xml = """
        <rss><channel>
        <item><title>Fresh headline</title><link>https://example.com/fresh</link><pubDate>Fri, 16 Oct 2026 12:00:00 +0800</pubDate></item>
        <item><title>Old headline</title><link>https://example.com/old</link><pubDate>Fri, 09 Oct 2026 12:00:00 +0800</pubDate></item>
        <item><title>Future headline</title><link>https://example.com/future</link><pubDate>Fri, 23 Oct 2026 12:00:00 +0800</pubDate></item>
        </channel></rss>
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: success ? 200 : 503, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: success ? (isRSS ? Data(xml.utf8) : BotInformationTests.chart()) : Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
