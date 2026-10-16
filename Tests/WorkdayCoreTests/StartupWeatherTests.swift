import XCTest
@testable import WorkdayCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
final class StartupWeatherTests: ChineseLocalizationTestCase {
    let fetched = Date(timeIntervalSince1970: 1792126800)
    var sample: Data { Data("{\"current\":{\"time\":1792126800,\"temperature_2m\":27.0,\"weather_code\":3}}".utf8) }
    func weather(_ data: Data? = nil) throws -> StartupWeather {
        try StartupWeather.decode(data ?? sample, city: "上海", latitude: 31.2304, longitude: 121.4737, fetchedAt: fetched)
    }
    func testRealResponseShapeIsStoredAndGreetingLocalizes() throws {
        let snapshot = try weather()
        XCTAssertEqual(snapshot.description(language: .simplifiedChinese), "阴 27.0°C")
        XCTAssertEqual(snapshot.description(language: .english), "Overcast 27.0°C")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let greetings = AIBot().startupGreeting(name: "小明", city: "上海", date: fetched, calendar: calendar, weather: snapshot)
        XCTAssertTrue(greetings["zh-Hans"]!.contains("Hi, 小明，今天是"))
        XCTAssertTrue(greetings["zh-Hans"]!.contains("天气阴 27.0°C（上海）"))
        XCTAssertTrue(greetings["en"]!.contains("Shanghai"))
        var message = AssistantMessage(role: .assistant, content: greetings["zh-Hans"]!, proactive: true, date: fetched)
        message.weather = snapshot; message.localizedContents = greetings
        XCTAssertEqual(try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(message)), message)
    }
    func testFailureNeverInventsWeatherAndStaleResponseIsRejected() throws {
        XCTAssertThrowsError(try weather(Data("{}".utf8)))
        XCTAssertThrowsError(try StartupWeather.decode(sample, city: "上海", latitude: 31, longitude: 121, fetchedAt: fetched.addingTimeInterval(11000)))
        let text = AIBot().startupGreeting(name: "", city: "上海", date: fetched, calendar: .current, weather: nil)
        XCTAssertTrue(text["zh-Hans"]!.contains("天气暂不可用"))
        XCTAssertFalse(text["zh-Hans"]!.contains("27.0"))
    }
    func testEachLaunchFetchesFreshWeatherWithoutCacheOrCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        WeatherProtocol.requests = []
        for _ in 0..<2 { _ = try await StartupWeatherClient().fetch(city: "上海", session: session) }
        XCTAssertEqual(WeatherProtocol.requests.count, 2)
        for request in WeatherProtocol.requests {
            XCTAssertEqual(request.url?.host, "api.open-meteo.com")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertTrue(request.url!.absoluteString.contains("timeformat=unixtime"))
        }
    }
}
private final class WeatherProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let data = Data("{\"current\":{\"time\":\(Date().timeIntervalSince1970),\"temperature_2m\":27,\"weather_code\":3}}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
