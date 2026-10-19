import Foundation

public enum ReportMood: Int, Codable { case happy, neutral, crying
    public static func overtime(_ seconds: TimeInterval) -> ReportMood {
        seconds < 15 * 60 ? .happy : seconds < 30 * 60 ? .neutral : .crying
    }
    public var title: String { switch self { case .happy: return L10n.text("加班不足 15 分钟"); case .neutral: return L10n.text("加班 15–不足30分钟"); case .crying: return L10n.text("加班至少 30 分钟") } }
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
    public var checklistItems: [BotTodo]?
    public var id: String { timeZoneID + "/" + dateKey }
    public func assistantSummary(hideEarnings: Bool, language: AppLanguage? = nil) -> String {
        var lines = [waterML < 1500
            ? L10n.text("今天喝水有点少哦，要多喝水才能促进代谢，身体才能棒棒～", language: language)
            : L10n.format("今天喝了{0}ml水，乖乖喝水的宝宝最棒了！", String(waterML), language: language)]
        if !hideEarnings, let earned {
            lines.append(L10n.format("今天收入{0}元，底薪到手，快乐下班～", String(Money.formatted(earned).dropFirst()), language: language))
        }
        switch ReportMood.overtime(overtimeSeconds) {
        case .happy: lines.append(L10n.text("今天没有加班，宝贝真棒～ 快点回去休息吧", language: language))
        case .neutral: lines.append(L10n.text("快点回家，不要让底薪被稀释", language: language))
        case .crying:
            let minutes = max(0, Int(overtimeSeconds / 60))
            lines.append(L10n.format("天呐噜！今天竟然加班 {0} h,{1} min，也太辛苦了吧，快点回家休息！明天不许这样了", String(minutes / 60), String(minutes % 60), language: language))
        }
        if let tasks = taskSummary(language: language) { lines.append(tasks) }
        return lines.joined(separator: "\n\n")
    }
    public func taskSummary(language: AppLanguage? = nil) -> String? {
        guard let checklistItems else { return nil }
        let done = checklistItems.filter(\.done).map(\.text)
        let pending = checklistItems.filter { !$0.done }.map(\.text)
        guard !checklistItems.isEmpty else { return L10n.text("今天没有待办事项记录。", language: language) }
        let separator = L10n.text("、", language: language)
        let completed = done.isEmpty ? L10n.text("今天尚未完成待办事项。", language: language)
            : L10n.format("今天已完成：{0}。", done.joined(separator: separator), language: language)
        return completed + " " + (pending.isEmpty ? L10n.text("今日待办已全部完成。", language: language)
            : L10n.format("还有{0}尚未完成，明天需要继续处理。", pending.joined(separator: separator), language: language))
    }
    /// A checkout snapshot is the source of truth, independent of earlier chat messages.
    public func assistantReport(hideEarnings: Bool, language: AppLanguage? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "HH:mm:ss"
        let checkoutTime = checkedOutAt.map(formatter.string(from:)) ?? L10n.text("未打卡", language: language)
        let income = hideEarnings ? L10n.text("已隐藏", language: language) : earned.map { Money.formatted($0) + L10n.text("（估算，非实际工资）", language: language) } ?? L10n.text("未设置薪资", language: language)
        return [
            L10n.format("日期：{0}", dateKey, language: language),
            L10n.format("时区：{0}", timeZoneID, language: language),
            L10n.format("计划下班：{0}", formatter.string(from: scheduledEnd), language: language),
            L10n.format("实际打卡：{0}", checkoutTime, language: language),
            L10n.format("饮水：{0} ml，共 {1} 杯（仅应用记录）", String(waterML), String(cups), language: language),
            L10n.format("今日收入：{0}", income, language: language),
            L10n.format("加班：{0}", OvertimeCalculator.duration(overtimeSeconds), language: language)
        ].joined(separator: "\n") + "\n\n" + assistantSummary(hideEarnings: hideEarnings, language: language)
    }
    public var mood: ReportMood? {
        guard isWorkday, checkedOutAt != nil || updatedAt >= scheduledEnd else { return nil }
        return .overtime(overtimeSeconds)
    }
    public var waterMessage: String {
        waterML < 1500 ? L10n.text("今天喝水有点少哦，要多喝水才能促进代谢哦～") : L10n.format("今天喝了{0}ml水，乖乖喝水的宝宝最棒了！", String(describing: waterML))
    }
    public var salaryMessage: String {
        guard let earned else { return L10n.text("设置薪资后，这里会记录每天的估算收入。") }
        return L10n.format("辛苦啦～今天收入{0}元，底薪到手，快乐下班～", String(describing: Money.formatted(earned).dropFirst()))
    }
    public var overtimeMessage: String {
        if !isWorkday { return L10n.text("今天休息，好好享受属于自己的时间吧～") }
        guard mood != nil else { return L10n.text("今天还没到下班时间，记得按时收工哦～") }
        switch ReportMood.overtime(overtimeSeconds) {
        case .happy: return L10n.text("今天没有加班，宝贝真棒～ 快点回去休息吧")
        case .neutral: return L10n.text("辛苦了，快点回家，不要让底薪被稀释")
        case .crying:
            let minutes = max(0, Int(overtimeSeconds / 60))
            return L10n.format("天呐噜！今天竟然加班 {0} h,{1} min，也太辛苦了吧，快点回家休息！明天不许这样了", String(describing: minutes / 60), String(describing: minutes % 60))
        }
    }
    public static func snapshot(now: Date, settings: WorkSettings, checkout: CheckoutRecord?, hydration: HydrationSummary, checklistItems: [BotTodo] = []) -> DailyReport {
        let work = ScheduleCalculator.snapshot(now: now, settings: settings)
        let checked = checkout?.applies(now: now, settings: settings) == true ? checkout?.checkedOutAt : nil
        let cutoff = checked ?? now
        let cutoffWork = ScheduleCalculator.snapshot(now: cutoff, settings: settings)
        let earnings = EarningsCalculator.calculate(now: cutoff, settings: settings, work: cutoffWork)
        return DailyReport(dateKey: work.dateKey, timeZoneID: settings.timeZoneID, updatedAt: now,
                           scheduledEnd: work.end, isWorkday: work.state != .rest,
                           waterML: hydration.totalML, cups: hydration.cups, earned: earnings.earned,
                           overtimeSeconds: work.state == .rest ? 0 : max(0, cutoff.timeIntervalSince(work.end)), checkedOutAt: checked, checklistItems: checklistItems)
    }
    public func validated() throws -> Self {
        guard let zone = TimeZone(identifier: timeZoneID) else { throw ValidationError(L10n.text("日报时区无效")) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard ScheduleCalculator.date(from: dateKey, calendar: calendar) != nil,
              ScheduleCalculator.key(updatedAt, calendar: calendar) == dateKey,
              ScheduleCalculator.key(scheduledEnd, calendar: calendar) == dateKey,
              waterML >= 0, cups >= 0, overtimeSeconds.isFinite, (0...86400).contains(overtimeSeconds),
              earned.map({ !$0.isNaN && $0 >= 0 && $0 <= 10_000_000 }) ?? true else { throw ValidationError(L10n.text("日报记录无效")) }
        if let checkedOutAt {
            guard checkedOutAt <= updatedAt, ScheduleCalculator.key(checkedOutAt, calendar: calendar) == dateKey else { throw ValidationError(L10n.text("日报打卡时间无效")) }
        }
        return self
    }
}

public struct DailyReportArchive: Codable, Equatable {
    public var schemaVersion = 1
    public private(set) var records: [DailyReport] = []
    public init() {}
    #if DEBUG
    public mutating func debugRemove(dateKey: String, timeZoneID: String) {
        records.removeAll { $0.dateKey == dateKey && $0.timeZoneID == timeZoneID }
    }
    #endif
    public mutating func upsert(_ report: DailyReport) throws {
        _ = try report.validated()
        if let index = records.firstIndex(where: { $0.id == report.id }) { if report.updatedAt >= records[index].updatedAt { records[index] = report } }
        else { records.append(report) }
        records.sort { $0.id < $1.id }
    }
    @discardableResult public mutating func editChecklistItem(reportID: String, itemID: UUID,
        text: String? = nil, done: Bool? = nil) throws -> Bool {
        guard var report = records.first(where: { $0.id == reportID }),
              let index = report.checklistItems?.firstIndex(where: { $0.id == itemID }),
              let item = report.checklistItems?[index] else { return false }
        report.checklistItems?[index] = try item.edited(text: text, done: done)
        // Historical report timestamps remain within their original calendar date.
        try upsert(report)
        return true
    }
    public static func decode(_ data: Data) throws -> Self {
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.schemaVersion == 1, Set(archive.records.map(\.id)).count == archive.records.count else { throw ValidationError(L10n.text("日报存储版本或记录重复异常")) }
        for report in archive.records { _ = try report.validated() }
        return archive
    }
}
