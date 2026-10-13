import Foundation

public enum ReportMood: Int, Codable { case happy, neutral, crying
    public static func overtime(_ seconds: TimeInterval) -> ReportMood {
        seconds < 15 * 60 ? .happy : seconds < 30 * 60 ? .neutral : .crying
    }
    public var title: String { switch self { case .happy: return "加班不足 15 分钟"; case .neutral: return "加班 15–不足30分钟"; case .crying: return "加班至少 30 分钟" } }
}

public struct DailyReport: Codable, Equatable, Identifiable {
    public var dateKey: String
    public var timeZoneID: String
    public var updatedAt: Date
    public var scheduledEnd: Date
    public var isWorkday: Bool
    public var waterML: Int
    public var cups: Int
    public var earned: Decimal?
    public var overtimeSeconds: TimeInterval
    public var checkedOutAt: Date?
    public var id: String { timeZoneID + "/" + dateKey }
    public var mood: ReportMood? {
        guard isWorkday, checkedOutAt != nil || updatedAt >= scheduledEnd else { return nil }
        return .overtime(overtimeSeconds)
    }
    public var waterMessage: String {
        waterML < 1500 ? "今天喝水有点少哦，要多喝水才能促进代谢哦～" : "今天喝了\(waterML)ml水，乖乖喝水的宝宝最棒了！"
    }
    public var salaryMessage: String {
        guard let earned else { return "设置薪资后，这里会记录每天的估算收入。" }
        return "辛苦啦～今天收入\(Money.formatted(earned).dropFirst())元，底薪到手，快乐下班～"
    }
    public var overtimeMessage: String {
        if !isWorkday { return "今天休息，好好享受属于自己的时间吧～" }
        guard mood != nil else { return "今天还没到下班时间，记得按时收工哦～" }
        switch ReportMood.overtime(overtimeSeconds) {
        case .happy: return "今天没有加班，宝贝真棒～ 快点回去休息吧"
        case .neutral: return "辛苦了，快点回家，不要让底薪被稀释"
        case .crying:
            let minutes = max(0, Int(overtimeSeconds / 60))
            return "天呐噜！今天竟然加班 \(minutes / 60) h,\(minutes % 60) min，也太辛苦了吧，快点回家休息！明天不许这样了"
        }
    }
    public static func snapshot(now: Date, settings: WorkSettings, checkout: CheckoutRecord?, hydration: HydrationSummary) -> DailyReport {
        let work = ScheduleCalculator.snapshot(now: now, settings: settings)
        let checked = checkout?.applies(now: now, settings: settings) == true ? checkout?.checkedOutAt : nil
        let cutoff = checked ?? now
        let cutoffWork = ScheduleCalculator.snapshot(now: cutoff, settings: settings)
        let earnings = EarningsCalculator.calculate(now: cutoff, settings: settings, work: cutoffWork)
        return DailyReport(dateKey: work.dateKey, timeZoneID: settings.timeZoneID, updatedAt: now,
                           scheduledEnd: work.end, isWorkday: work.state != .rest,
                           waterML: hydration.totalML, cups: hydration.cups, earned: earnings.earned,
                           overtimeSeconds: work.state == .rest ? 0 : max(0, cutoff.timeIntervalSince(work.end)), checkedOutAt: checked)
    }
    public func validated() throws -> Self {
        guard let zone = TimeZone(identifier: timeZoneID) else { throw ValidationError("日报时区无效") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard ScheduleCalculator.date(from: dateKey, calendar: calendar) != nil,
              ScheduleCalculator.key(updatedAt, calendar: calendar) == dateKey,
              ScheduleCalculator.key(scheduledEnd, calendar: calendar) == dateKey,
              waterML >= 0, cups >= 0, overtimeSeconds.isFinite, (0...86400).contains(overtimeSeconds),
              earned.map({ !$0.isNaN && $0 >= 0 && $0 <= 10_000_000 }) ?? true else { throw ValidationError("日报记录无效") }
        if let checkedOutAt {
            guard checkedOutAt <= updatedAt, ScheduleCalculator.key(checkedOutAt, calendar: calendar) == dateKey else { throw ValidationError("日报打卡时间无效") }
        }
        return self
    }
}

public struct DailyReportArchive: Codable, Equatable {
    public var schemaVersion = 1
    public private(set) var records: [DailyReport] = []
    public init() {}
    public mutating func upsert(_ report: DailyReport) throws {
        _ = try report.validated()
        if let index = records.firstIndex(where: { $0.id == report.id }) { if report.updatedAt >= records[index].updatedAt { records[index] = report } }
        else { records.append(report) }
        records.sort { $0.id < $1.id }
    }
    public static func decode(_ data: Data) throws -> Self {
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.schemaVersion == 1, Set(archive.records.map(\.id)).count == archive.records.count else { throw ValidationError("日报存储版本或记录重复异常") }
        for report in archive.records { _ = try report.validated() }
        return archive
    }
}
