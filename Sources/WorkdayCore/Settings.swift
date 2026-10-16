import Foundation

public enum PayMode: String, Codable, CaseIterable { case fixedDays, plannedDays, customDaily
    public var title: String { switch self { case .fixedDays: return L10n.text("固定月计薪天数"); case .plannedDays: return L10n.text("当月计划工作日"); case .customDaily: return L10n.text("自定义日薪") } }
}
public enum MenuMode: String, Codable, CaseIterable { case countdown, earnings, icon
    public var title: String { switch self { case .countdown: return L10n.text("下班倒计时"); case .earnings: return L10n.text("今日工资"); case .icon: return L10n.text("仅图标") } }
}
public enum ReminderCategory: String, Codable, CaseIterable { case walk, water, eyes
    public var title: String { switch self { case .walk: return L10n.text("走动"); case .water: return L10n.text("喝水"); case .eyes: return L10n.text("护眼") } }
}
public enum PetKind: String, Codable, CaseIterable { case bunGirl, worker, cat, dog, goldfish, fox, custom
    public var title: String { switch self { case .cat: return L10n.text("下班猫"); case .dog: return L10n.text("摸鱼狗"); case .worker: return L10n.text("打工人"); case .goldfish: return L10n.text("小金鱼"); case .fox: return L10n.text("小狐妖"); case .bunGirl: return L10n.text("丸子头女生"); case .custom: return L10n.text("自定义动画") } }
    public var isOfficeWorker: Bool { self == .worker || self == .bunGirl }
}
public extension PetKind {
    func next(customAvailable: Bool) -> PetKind {
        let choices = Self.allCases.filter { $0 != .custom || customAvailable }
        guard let index = choices.firstIndex(of: self) else { return choices[0] }
        return choices[(index + 1) % choices.count]
    }
}
public struct WorkSettings: Codable, Equatable {
    public var schemaVersion = 1
    public var timeZoneID = TimeZone.current.identifier
    public var weekdays: Set<Int> = [2,3,4,5,6]
    public var startMinute = 9 * 60
    public var dailyStartMinutes: [String: Int] = [:]
    /// Elapsed shift length, including any unpaid lunch break.
    public var workDurationMinutes = 9 * 60
    /// Compatibility accessor; only workDurationMinutes is persisted.
    public var endMinute: Int {
        get { startMinute + workDurationMinutes }
        set { workDurationMinutes = newValue - startMinute }
    }
    public var lunchEnabled = true
    public var lunchStart = 12 * 60
    public var lunchEnd = 13 * 60
    public var overrides: [String: Bool] = [:]
    public var monthlySalary: Decimal? = nil
    public var payMode = PayMode.fixedDays
    public var fixedDays = Decimal(string: "21.75")!
    public var customDaily: Decimal? = nil
    public var hideEarnings = false
    public var hourlyEnabled = true
    public var categories: Set<ReminderCategory> = Set(ReminderCategory.allCases)
    public var notificationSound = true
    public var speechEnabled = false
    public var offworkEnabled = true
    public var menuMode = MenuMode.countdown
    public var petEnabled = true
    public var petKind = PetKind.cat
    public var customPet: CustomPetConfiguration? = nil
    public var petAlwaysOnTop = true
    public var chatPanelPosition = ChatPanelPosition.right
    public var overtimeEnabled = true
    public var overtimeIntervalMinutes = 5
    public var cupVolumeML = 500
    public init() {}
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        c.locale = L10n.locale
        return c
    }
    public func startMinute(on date: Date) -> Int { dailyStartMinutes[ScheduleCalculator.key(date, calendar: calendar)] ?? startMinute }
    /// Preserve the configured shift length when a day has a custom start.
    public func endMinute(on date: Date) -> Int { startMinute(on: date) + workDurationMinutes }
    public func validated() throws -> WorkSettings {
        if let customPet { _ = try customPet.validated() }
        if petKind == .custom && customPet == nil { throw ValidationError(L10n.text("请先导入自定义序列帧图集")) }
        guard (1...240).contains(overtimeIntervalMinutes) else { throw ValidationError(L10n.text("加班提示间隔须为 1–240 分钟的整数")) }
        guard (1...2000).contains(cupVolumeML) else { throw ValidationError(L10n.text("每杯水量须为 1–2000 ml 的整数")) }
        guard schemaVersion == 1 else { throw ValidationError(L10n.text("配置版本不受支持")) }
        guard TimeZone(identifier: timeZoneID) != nil else { throw ValidationError(L10n.text("请选择有效工作时区")) }
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1...7).contains($0) }) else { throw ValidationError(L10n.text("至少选择一个常规工作日")) }
        guard (0..<1440).contains(startMinute), (1..<1440).contains(workDurationMinutes), endMinute < 1440 else { throw ValidationError(L10n.text("弹性上班工时须大于 0，且计算后的下班时间不能跨天")) }
        guard (0..<1440).contains(lunchStart), (0..<1440).contains(lunchEnd) else { throw ValidationError(L10n.text("午休时间须为有效的当天时间")) }
        if lunchEnabled {
            guard startMinute < lunchStart, lunchStart < lunchEnd, lunchEnd < endMinute else { throw ValidationError(L10n.text("午休必须满足：上班 < 午休开始 < 午休结束 < 下班")) }
        }
        guard Money.valid(fixedDays, maximum: 31), fixedDays >= 1 else { throw ValidationError(L10n.text("计薪天数须为 1–31，最多两位小数")) }
        if let salary = monthlySalary, !Money.valid(salary) { throw ValidationError(L10n.text("月薪须为 0–10000000，最多两位小数")) }
        if let daily = customDaily, !Money.valid(daily) { throw ValidationError(L10n.text("自定义日薪须为 0–10000000，最多两位小数")) }
        if payMode == .customDaily && customDaily == nil { throw ValidationError(L10n.text("请填写自定义日薪")) }
        for (key, minute) in dailyStartMinutes {
            guard ScheduleCalculator.date(from: key, calendar: calendar) != nil, (0..<1440).contains(minute), minute + workDurationMinutes < 1440 else { throw ValidationError(L10n.format("{0} 的弹性上班时间必须为有效当天时间，且计算后的下班时间不能跨天", String(describing: key))) }
        }
        for key in overrides.keys { guard ScheduleCalculator.date(from: key, calendar: calendar) != nil else { throw ValidationError(L10n.text("日期覆盖格式应为有效 yyyy-MM-dd")) } }
        return self
    }
}
public struct ValidationError: LocalizedError { public let message: String; public init(_ message: String) { self.message = message }; public var errorDescription: String? { message } }
public enum Money {
    public static func parse(_ input: String, maximum: Decimal = 10_000_000) throws -> Decimal? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let pattern = #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let value = Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")), valid(value, maximum: maximum) else {
            throw ValidationError(L10n.format("请输入 0–{0} 的金额，最多两位小数；千位逗号应每三位分组", String(describing: maximum)))
        }
        return value
    }
    public static func valid(_ value: Decimal, maximum: Decimal = 10_000_000) -> Bool {
        guard !value.isNaN, value >= 0, value <= maximum else { return false }
        var original = value; var rounded = Decimal(); NSDecimalRound(&rounded, &original, 2, .plain)
        return rounded == value
    }
    public static func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2; formatter.roundingMode = .halfUp
        return "¥" + (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.00")
    }
    public static func input(_ value: Decimal?) -> String { value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" }
}

/// Version-zero documents used the same fields but lacked a schema marker.
/// Defaults fill newly introduced fields; malformed or future versions recover safely.
public enum SettingsCodec {
    public static func decode(_ data: Data) throws -> WorkSettings {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ValidationError(L10n.text("配置格式损坏")) }
        let version = object["schemaVersion"] as? Int ?? 0
        guard version <= 1 && version >= 0 else { throw ValidationError(L10n.text("配置来自较新版本")) }
        // Migrate the old fixed end time once; the duration is the only stored shift length.
        if object["workDurationMinutes"] == nil {
            guard object["startMinute"] == nil || object["startMinute"] is Int,
                  object["endMinute"] == nil || object["endMinute"] is Int else { throw ValidationError(L10n.text("工作时间格式损坏")) }
            let start = object["startMinute"] as? Int ?? 9 * 60
            let end = object["endMinute"] as? Int ?? 18 * 60
            object["workDurationMinutes"] = end - start
        }
        object.removeValue(forKey: "endMinute")
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkSettings())) as! [String: Any]
        for (key, value) in defaults where object[key] == nil { object[key] = value }
        object["schemaVersion"] = 1
        return try JSONDecoder().decode(WorkSettings.self, from: JSONSerialization.data(withJSONObject: object)).validated()
    }
}
public protocol Clock { var now: Date { get } }
public struct SystemClock: Clock { public init() {}; public var now: Date { Date() } }
public struct FixedClock: Clock { public var now: Date; public init(_ now: Date) { self.now = now } }
