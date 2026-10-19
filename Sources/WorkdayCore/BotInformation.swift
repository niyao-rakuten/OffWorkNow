import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum BotNewsTopic: String, Equatable, Sendable { case headlines, economy, politics }
public enum BotMarketScope: String, Equatable, Sendable { case overview, stocks, gold, bitcoin, nasdaq, dow, china, nikkei }
public enum BotInformationRequest: Equatable, Sendable {
    case news(BotNewsTopic), markets(BotMarketScope), searchNews(String)
    public static func interpret(_ input: String) -> Self? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^(?:请|帮我|请帮我)?(?:搜索|搜一下|搜|查找|查一下)\s*(?:关于|有关)?(.*?)\s*(?:的)?(?:相关的?新闻|相关的?报道|新闻报道|新闻|报道)[。！？?!]*$"#,
            #"^(?:新闻搜索|搜索新闻)\s*[:：]\s*(.*?)[。！？?!]*$"#,
            #"^(?:(?:search|find)\s+(?:for\s+)?news\s+(?:about|on)\s+|news\s+about\s+)(.+?)[?!]*$"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
               let range = Range(match.range(at: 1), in: original) {
                let topic = String(original[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "“”\"‘’"))
                return .searchNews(topic)
            }
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "？?！!。"))
        switch text {
        case "新闻", "今日新闻", "今天新闻", "热点新闻", "news", "todaynews", "today'snews": return .news(.headlines)
        case "经济新闻", "财经新闻", "财经资讯", "businessnews", "economicnews": return .news(.economy)
        case "政治新闻", "时政新闻", "politicalnews", "politicsnews": return .news(.politics)
        case "黄金走势", "黄金行情", "gold", "goldtrend", "goldprice": return .markets(.gold)
        case "btc走势", "btc行情", "比特币走势", "比特币行情", "btc", "bitcoin", "bitcointrend": return .markets(.bitcoin)
        case "股市走势", "股市行情", "stockmarket", "stockmarkettrend": return .markets(.stocks)
        case "金融市场", "市场行情", "大盘", "大盘走势", "marketoverview", "markets": return .markets(.overview)
        case "纳指走势", "纳指", "纳斯达克走势", "nasdaq": return .markets(.nasdaq)
        case "道指走势", "道指", "dow", "dowjones": return .markets(.dow)
        case "a股走势", "a股行情", "a股": return .markets(.china)
        case "日经走势", "日经", "nikkei": return .markets(.nikkei)
        default: return nil
        }
    }
}

public struct BotNewsItem: Equatable, Sendable {
    public let title: String
    public let url: URL
    public let date: Date
    public let sourceName: String?
    public let sourceURL: URL?
}

/// RSS only: never loads article HTML, external XML entities or embedded media.
public enum BotNewsParser {
    public static func parse(_ data: Data) throws -> [BotNewsItem] {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw URLError(.cannotParseResponse) }
        return delegate.items
    }
    private final class FeedDelegate: NSObject, XMLParserDelegate {
        var items: [BotNewsItem] = []
        var inside = false, field = "", values: [String: String] = [:]
        var sourceURL: URL?
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == "item" { inside = true; values = [:]; sourceURL = nil }
            field = name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
            if inside, field == "source", let value = attributes["url"] { sourceURL = webURL(value) }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inside { values[field, default: ""] += string }
        }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            if let value = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: value) }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { field = "" }
            guard name == "item" else { return }
            inside = false
            var title = (values["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let link = webURL(values["link"] ?? "") else { return }
            // Bing provides the original article URL as a query item. Google uses
            // opaque redirect links: keep those intact instead of inventing article URLs.
            var url = link
            if ["www.bing.com", "bing.com"].contains(link.host?.lowercased() ?? ""), link.path == "/news/apiclick.aspx",
               let destination = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
               let articleURL = webURL(destination) { url = articleURL }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            guard let date = formatter.date(from: (values["pubdate"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            let source = (values["source"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty, title.hasSuffix(" - " + source) { title.removeLast(source.count + 3) }
            items.append(BotNewsItem(title: String(title.prefix(300)), url: url, date: date,
                                     sourceName: source.isEmpty ? nil : String(source.prefix(120)), sourceURL: sourceURL))
        }
        private func webURL(_ value: String) -> URL? {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return url
        }
    }
}

public struct BotMarketQuote: Equatable, Sendable {
    public let price: Double
    public let previousClose: Double?
    public let currency: String
    public let observedAt: Date
    public let closes: [Double]
    public var changePercent: Double? { previousClose.map { (price / $0 - 1) * 100 } }
    public var monthPercent: Double? { closes.first.map { (price / $0 - 1) * 100 } }
    public static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        struct Response: Decodable {
            struct Chart: Decodable {
                struct Result: Decodable {
                    struct Meta: Decodable { let regularMarketPrice: Double; let regularMarketTime: Double; let chartPreviousClose: Double?; let previousClose: Double?; let currency: String?; let exchangeTimezoneName: String? }
                    struct Indicators: Decodable { struct Quote: Decodable { let close: [Double?] }; let quote: [Quote] }
                    let meta: Meta; let timestamp: [Double]; let indicators: Indicators
                }
                let result: [Result]?
            }
            let chart: Chart
        }
        guard let result = try JSONDecoder().decode(Response.self, from: data).chart.result?.first else { throw URLError(.cannotParseResponse) }
        let meta = result.meta
        guard meta.regularMarketPrice.isFinite, meta.regularMarketPrice > 0, meta.regularMarketTime.isFinite,
              meta.regularMarketTime > 0, meta.regularMarketTime <= now.timeIntervalSince1970 + 300 else { throw URLError(.cannotParseResponse) }
        let candles = zip(result.timestamp, result.indicators.quote.first?.close ?? []).compactMap { time, close -> (Date, Double)? in
            guard time.isFinite, time > 0, time <= now.timeIntervalSince1970 + 300,
                  let close, close.isFinite, close > 0 else { return nil }
            return (Date(timeIntervalSince1970: time), close)
        }.sorted { $0.0 < $1.0 }
        let closes = candles.map { $0.1 }
        // chartPreviousClose is BEFORE THE REQUESTED RANGE. Find the previous
        // exchange-calendar day so a null/absent current candle cannot shift the baseline.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = meta.exchangeTimezoneName.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)!
        let quoteDate = Date(timeIntervalSince1970: meta.regularMarketTime)
        let previousCandle = candles.last { calendar.startOfDay(for: $0.0) < calendar.startOfDay(for: quoteDate) }?.1
        let prior = meta.previousClose ?? previousCandle
        return Self(price: meta.regularMarketPrice, previousClose: prior.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
                    currency: meta.currency ?? "", observedAt: Date(timeIntervalSince1970: meta.regularMarketTime), closes: closes)
    }
}

/// Public-source retrieval, separate from deterministic AIBot decisions and OpenRouter.
/// The chart endpoint is unofficial and may be delayed, rate-limited or changed by Yahoo.
public struct BotInformationClient: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func fetch(_ request: BotInformationRequest, now: Date = Date()) async throws -> [String: String] {
        switch request {
        case .searchNews(let topic): return try await searchNews(topic, now: now)
        case .news(let topic): return try await news(topic, now: now)
        case .markets(let scope): return try await markets(scope, now: now)
        }
    }
    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("OffWorkNow/1.2 (personal news reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
    public static func status(_ zh: String, _ en: String) -> [String: String] { ["zh-Hans": zh, "en": en] }
    private func stamp(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"; return f.string(from: date)
    }
    private func safe(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "\n", with: " ")
    }
    private struct Feed: Sendable { let name: String; let url: String }
    private func news(_ topic: BotNewsTopic, now: Date) async throws -> [String: String] {
        let domestic = topic == .economy ? "finance" : topic == .politics ? "china" : "scroll-news"
        let overseas = topic == .economy ? "business" : "world"
        let feeds = [Feed(name: "中新网 · China News Service", url: "https://www.chinanews.com.cn/rss/\(domestic).xml"),
                     Feed(name: "BBC", url: "https://feeds.bbci.co.uk/news/\(overseas)/rss.xml"),
                     Feed(name: "CNBC", url: "https://www.cnbc.com/id/\(topic == .economy ? "10001147" : "100727362")/device/rss/rss.html")]
        let results = await withTaskGroup(of: (Int, [BotNewsItem]?).self) { group in
            for (i, feed) in feeds.enumerated() { group.addTask {
                do { return (i, try BotNewsParser.parse(await get(URL(string: feed.url)!))) } catch { return (i, nil) }
            } }
            var values: [(Int, [BotNewsItem]?)] = []; for await value in group { values.append(value) }; return values.sorted { $0.0 < $1.0 }
        }
        try Task.checkCancellation()
        var zh = "## 新闻速览\n\n抓取时间：\(stamp(now))\n\n", en = "## News digest\n\nFetched: \(stamp(now))\n\n"
        var seen = Set<String>()
        for (i, items) in results {
            zh += "### \(feeds[i].name)\n\n"; en += "### \(feeds[i].name)\n\n"
            guard let items else { zh += "暂时无法获取此来源。\n\n"; en += "Source temporarily unavailable.\n\n"; continue }
            let recent = items.sorted { $0.date > $1.date }.filter { $0.date <= now.addingTimeInterval(300) && $0.date >= now.addingTimeInterval(-172800) }
            var count = 0
            for item in recent where count < 4 {
                guard seen.insert(item.url.absoluteString).inserted else { continue }; count += 1
                let line = "- [\(safe(item.title))](\(item.url.absoluteString)) — \(stamp(item.date))\n"
                zh += line; en += line
            }
            if count == 0 { zh += "近 48 小时暂无可用新闻。\n"; en += "No available items from the last 48 hours.\n" }
            zh += "\n"; en += "\n"
        }
        zh += "按媒体近期发布内容汇总，并非热度排名；标题保留原文，点击查看报道。"
        en += "Recent publisher headlines, not a popularity ranking. Titles remain in their original language; open the links for reporting."
        return Self.status(zh, en)
    }
    /// Search-provider URLs are built from query items, preserving spaces, case and '&'.
    public static func newsSearchURLs(topic: String) -> [URL] {
        let chinese = topic.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
        var google = URLComponents(string: "https://news.google.com/rss/search")!
        google.queryItems = [.init(name: "q", value: topic + " when:7d"), .init(name: "hl", value: chinese ? "zh-CN" : "en-US"),
                             .init(name: "gl", value: chinese ? "CN" : "US"), .init(name: "ceid", value: chinese ? "CN:zh-Hans" : "US:en")]
        var bing = URLComponents(string: "https://www.bing.com/news/search")!
        bing.queryItems = [.init(name: "q", value: topic), .init(name: "format", value: "rss"), .init(name: "setlang", value: chinese ? "zh-hans" : "en-US"), .init(name: "mkt", value: chinese ? "zh-CN" : "en-US")]
        return [google.url!, bing.url!]
    }
    private func searchNews(_ topic: String, now: Date) async throws -> [String: String] {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return Self.status("请输入新闻主题，例如：搜索中东石油战争的相关新闻。", "Enter a news topic, for example: search news about Middle East oil conflict.") }
        guard topic.count <= 200 else { return Self.status("新闻主题过长，请缩短到 200 字以内。", "Please shorten the news topic to 200 characters or fewer.") }
        let urls = Self.newsSearchURLs(topic: topic)
        let results = await withTaskGroup(of: (Int, [BotNewsItem]?).self) { group in
            for (i, url) in urls.enumerated() { group.addTask {
                do { return (i, try BotNewsParser.parse(await get(url))) } catch { return (i, nil) }
            } }
            var values: [(Int, [BotNewsItem]?)] = []; for await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }
        try Task.checkCancellation()
        var zh = "## 主题新闻搜索\n\n主题：\(safe(topic))\n\n查询时间：\(stamp(now))\n\n"
        var en = "## Topic news search\n\nTopic: \(safe(topic))\n\nRequested: \(stamp(now))\n\n"
        let failed = results.filter { $0.1 == nil }.map { $0.0 == 0 ? "Google News" : "Bing News" }
        if failed.count == urls.count {
            return Self.status(zh + "暂时无法连接新闻搜索源，请检查网络后重试。", en + "News search providers are unavailable. Check your connection and retry.")
        }
        var seenURLs = Set<String>(), seenTitles = Set<String>()
        let items = results.flatMap { $0.1 ?? [] }.filter {
            $0.date <= now.addingTimeInterval(300) && $0.date >= now.addingTimeInterval(-7 * 86400)
        }.sorted { $0.date > $1.date }.filter { item in
            let title = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .filter { !$0.isWhitespace }
            guard !seenURLs.contains(item.url.absoluteString), !seenTitles.contains(title) else { return false }
            seenURLs.insert(item.url.absoluteString); seenTitles.insert(title); return true
        }
        // Cap each outlet to preserve source diversity; preserve newest-first outlet order.
        var groups: [(name: String, items: [BotNewsItem])] = [], count = 0
        for item in items where count < 16 {
            let name = item.sourceName ?? item.sourceURL?.host ?? item.url.host ?? "Unknown source"
            if let index = groups.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                guard groups[index].items.count < 3 else { continue }
                groups[index].items.append(item)
            } else { groups.append((name, [item])) }
            count += 1
        }
        if groups.isEmpty {
            zh += "近 7 天未找到匹配报道，可以换用更简短的关键词。\n\n"
            en += "No matching reports from the last 7 days. Try shorter keywords.\n\n"
        }
        for group in groups {
            let heading = "### \(safe(group.name))\n\n"; zh += heading; en += heading
            for item in group.items {
                let line = "- [\(safe(item.title))](\(item.url.absoluteString)) — \(stamp(item.date))\n"
                zh += line; en += line
            }
            zh += "\n"; en += "\n"
        }
        if !failed.isEmpty {
            zh += "部分搜索源暂不可用：\(failed.joined(separator: ", "))。以上为已获取的结果。\n\n"
            en += "Some providers are unavailable: \(failed.joined(separator: ", ")). Showing available results.\n\n"
        }
        zh += "搜索来源：Google News / Bing News；媒体名称来自订阅元数据。范围为近 7 天，最多 16 条、每家媒体最多 3 条；标题保留原文，部分链接经新闻聚合平台跳转。不代表全网完整报道。"
        en += "Search: Google News / Bing News; outlet names come from feed metadata. Last 7 days, up to 16 reports and 3 per outlet. Original titles; some links redirect through news aggregators. Coverage is not exhaustive."
        return Self.status(zh, en)
    }
    private struct Instrument: Sendable { let symbol: String; let zh: String; let en: String; let scope: BotMarketScope }
    private func markets(_ scope: BotMarketScope, now: Date) async throws -> [String: String] {
        let all: [Instrument] = [
            .init(symbol: "^IXIC", zh: "纳斯达克综合指数", en: "Nasdaq Composite", scope: .nasdaq),
            .init(symbol: "^DJI", zh: "道琼斯工业指数", en: "Dow Jones Industrial Average", scope: .dow),
            .init(symbol: "000001.SS", zh: "上证综合指数", en: "Shanghai Composite", scope: .china),
            .init(symbol: "399001.SZ", zh: "深证成指", en: "Shenzhen Component", scope: .china),
            .init(symbol: "^N225", zh: "日经 225", en: "Nikkei 225", scope: .nikkei),
            .init(symbol: "BTC-USD", zh: "比特币 / 美元", en: "Bitcoin / USD", scope: .bitcoin),
            .init(symbol: "GC=F", zh: "黄金期货（非现货，美元/盎司）", en: "Gold futures (not spot, USD/oz)", scope: .gold)]
        let instruments = all.filter { scope == .overview || (scope == .stocks && $0.scope != .bitcoin && $0.scope != .gold) || $0.scope == scope }
        let results = await withTaskGroup(of: (Int, BotMarketQuote?).self) { group in
            for (i, instrument) in instruments.enumerated() { group.addTask {
                var url = URLComponents(string: "https://query1.finance.yahoo.com")!
                url.path = "/v8/finance/chart/" + instrument.symbol
                url.queryItems = [.init(name: "interval", value: "1d"), .init(name: "range", value: "1mo")]
                do { return (i, try BotMarketQuote.decode(await get(url.url!), now: now)) } catch { return (i, nil) }
            } }
            var values: [(Int, BotMarketQuote?)] = []; for await value in group { values.append(value) }; return values.sorted { $0.0 < $1.0 }
        }
        try Task.checkCancellation()
        var zh = "## 市场行情\n\n查询时间：\(stamp(now))\n\n", en = "## Market overview\n\nRequested: \(stamp(now))\n\n"
        func number(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
        func percent(_ value: Double?) -> String { value.map { String(format: "%+.2f%%", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "—" }
        for (i, quote) in results {
            let instrument = instruments[i]
            let url = URL(string: "https://finance.yahoo.com/quote/")!.appendingPathComponent(instrument.symbol).absoluteString
            zh += "### [\(instrument.zh)](\(url))\n\n"; en += "### [\(instrument.en)](\(url))\n\n"
            guard let quote else { zh += "数据暂不可用，请稍后重试。\n\n"; en += "Data unavailable; please retry later.\n\n"; continue }
            let unit = instrument.scope == .gold || instrument.scope == .bitcoin ? quote.currency : ""
            zh += "最新：**\(number(quote.price)) \(unit)**\n\n较前一交易日收盘：\(percent(quote.changePercent))\n\n近月变化：\(percent(quote.monthPercent))\n\n报价时间：\(stamp(quote.observedAt))\n\n"
            en += "Latest: **\(number(quote.price)) \(unit)**\n\nVs previous daily close: \(percent(quote.changePercent))\n\nOne-month change: \(percent(quote.monthPercent))\n\nQuote time: \(stamp(quote.observedAt))\n\n"
            if quote.closes.count > 1 {
                let samples = quote.closes.suffix(10).map(number).joined(separator: " → ")
                zh += "最近 \(min(10, quote.closes.count)) 个日线收盘（由早到晚）：\n\n\(samples)\n\n"
                en += "Last \(min(10, quote.closes.count)) daily closes (oldest first):\n\n\(samples)\n\n"
            }
            if now.timeIntervalSince(quote.observedAt) > 86400 { zh += "此报价超过 24 小时，可能休市或数据延迟。\n\n"; en += "Quote is over 24 hours old; the market may be closed or data delayed.\n\n" }
        }
        zh += "来源：Yahoo Finance。行情可能延迟；日线末点可能为未收盘数据，近月按可用首点计算。BTC 涨跌按日线口径，不是滚动 24 小时。"
        en += "Source: Yahoo Finance. Quotes may be delayed; the latest daily candle may be incomplete. Month change uses the first available sample. BTC change uses daily candles, not rolling 24 hours."
        return Self.status(zh, en)
    }
}
