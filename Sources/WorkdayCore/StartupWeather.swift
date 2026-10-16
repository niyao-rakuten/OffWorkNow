import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StartupWeather: Codable, Equatable, Sendable {
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let temperatureC: Double
    public let code: Int
    public let observedAt: Date
    public let fetchedAt: Date
    public let source: String
    public static func decode(_ data: Data, city: String, latitude: Double, longitude: Double, fetchedAt: Date) throws -> Self {
        struct Response: Decodable {
            struct Current: Decodable { let time: Double; let temperature_2m: Double; let weather_code: Int }
            let current: Current
        }
        let value = try JSONDecoder().decode(Response.self, from: data).current
        guard value.temperature_2m.isFinite, (-100...70).contains(value.temperature_2m),
              value.time.isFinite, abs(fetchedAt.timeIntervalSince1970 - value.time) < 10800 else {
            throw ValidationError(L10n.text("天气数据无效或已过期"))
        }
        return Self(city: city, latitude: latitude, longitude: longitude, temperatureC: value.temperature_2m,
                    code: value.weather_code, observedAt: Date(timeIntervalSince1970: value.time), fetchedAt: fetchedAt, source: "Open-Meteo")
    }
    public func description(language: AppLanguage) -> String {
        let key: String
        switch code {
        case 0: key = "晴"
        case 1: key = "晴间多云"
        case 2: key = "多云"
        case 3: key = "阴"
        case 45, 48: key = "雾"
        case 51, 53, 55: key = "毛毛雨"
        case 56, 57, 66, 67: key = "冻雨"
        case 61: key = "小雨"
        case 63: key = "中雨"
        case 65: key = "大雨"
        case 71, 73, 75, 77: key = "雪"
        case 80, 81, 82: key = "阵雨"
        case 85, 86: key = "阵雪"
        case 95, 96, 97, 99: key = "雷暴"
        default: key = "天气状况未知"
        }
        return L10n.text(key, language: language) + " " + String(format: "%.1f°C", temperatureC)
    }
}

/// Each fetch bypasses URL caches. Never substitutes a forecast from an earlier launch.
public struct StartupWeatherClient {
    public init() {}
    public func fetch(city: String, session: URLSession = .shared) async throws -> StartupWeather {
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { throw ValidationError(L10n.text("请设置天气城市")) }
        var latitude = 31.2304, longitude = 121.4737
        if !["上海", "上海市", "shanghai"].contains(city.lowercased()) {
            var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            url.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en")]
            struct Geocoding: Decodable {
                struct Place: Decodable { let latitude: Double; let longitude: Double }
                let results: [Place]?
            }
            let data = try await request(url.url!, session: session)
            guard let place = try JSONDecoder().decode(Geocoding.self, from: data).results?.first,
                  place.latitude.isFinite, place.longitude.isFinite,
                  (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else {
                throw ValidationError(L10n.text("未找到天气城市，请检查城市名称"))
            }
            latitude = place.latitude; longitude = place.longitude
        }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [URLQueryItem(name: "latitude", value: String(latitude)), URLQueryItem(name: "longitude", value: String(longitude)),
                          URLQueryItem(name: "current", value: "temperature_2m,weather_code"), URLQueryItem(name: "timeformat", value: "unixtime"),
                          URLQueryItem(name: "forecast_days", value: "1")]
        let data = try await request(url.url!, session: session)
        return try StartupWeather.decode(data, city: city, latitude: latitude, longitude: longitude, fetchedAt: Date())
    }
    private func request(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ValidationError(L10n.text("天气服务暂不可用"))
        }
        return data
    }
}

extension AIBot {
    public func startupGreeting(name: String, city: String, date: Date, calendar: Calendar,
                                weather: StartupWeather?, pending: Bool = false) -> [String: String] {
        Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map { language in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let owner = name.isEmpty || name == "主人" ? L10n.text("主人", language: language) : name
            let place = ["上海", "上海市", "shanghai"].contains(city.lowercased()) ? L10n.text("上海", language: language) : city
            let condition = weather?.description(language: language) ?? L10n.text(pending ? "正在获取天气…" : "天气暂不可用", language: language)
            let label = AssistantTimeline.dateLabel(date, calendar: calendar, language: language)
            let dateText = language == .simplifiedChinese ? label.replacingOccurrences(of: " ", with: "，") : label
            let text = L10n.format("Hi, {0}，今天是{1}，天气{2}（{3}），又是新的一天，今天也要元气满满努力工作哦～", owner,
                                   dateText, condition, place, language: language)
            return (language.rawValue, text)
        })
    }
}
