import Foundation

public struct WaterCup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let volumeML: Int
    public init(date: Date, volumeML: Int) { id = UUID(); self.date = date; self.volumeML = volumeML }
}
public struct HydrationSummary: Equatable {
    public let cups: Int
    public let totalML: Int
    public init(cups: Int, totalML: Int) { self.cups = cups; self.totalML = totalML }
    public var title: String { "今天 \(cups) 杯 · \(totalML) ml" }
}
public struct HydrationLog: Codable, Equatable {
    public let schemaVersion: Int
    public let dateKey: String
    public let timeZoneID: String
    public private(set) var entries: [WaterCup]
    public init(now: Date, settings: WorkSettings) {
        schemaVersion = 1; dateKey = ScheduleCalculator.key(now, calendar: settings.calendar); timeZoneID = settings.timeZoneID; entries = []
    }
    public func applies(now: Date, settings: WorkSettings) -> Bool { dateKey == ScheduleCalculator.key(now, calendar: settings.calendar) && timeZoneID == settings.timeZoneID }
    public func summary(now: Date, settings: WorkSettings) -> HydrationSummary {
        guard applies(now: now, settings: settings) else { return HydrationSummary(cups: 0, totalML: 0) }
        let current = entries.filter { $0.date <= now }
        return HydrationSummary(cups: current.count, totalML: current.reduce(0) { $0 + $1.volumeML })
    }
    public mutating func add(now: Date, settings: WorkSettings) throws {
        guard (1...2000).contains(settings.cupVolumeML) else { throw ValidationError("每杯水量须为 1–2000 ml 的整数") }
        if !applies(now: now, settings: settings) { self = HydrationLog(now: now, settings: settings) }
        entries.append(WaterCup(date: now, volumeML: settings.cupVolumeML))
    }
    public mutating func undoLast(now: Date, settings: WorkSettings) {
        guard applies(now: now, settings: settings), let index = entries.lastIndex(where: { $0.date <= now }) else { return }
        entries.remove(at: index)
    }
    public func validated() throws -> HydrationLog {
        guard schemaVersion == 1, let zone = TimeZone(identifier: timeZoneID) else { throw ValidationError("喝水记录版本或时区无效") }
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        guard ScheduleCalculator.date(from: dateKey, calendar: c) != nil,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ (1...2000).contains($0.volumeML) && ScheduleCalculator.key($0.date, calendar: c) == dateKey }) else { throw ValidationError("喝水记录损坏") }
        return self
    }
}
public enum HydrationCalculator {
    public static func parseCupVolume(_ input: String) throws -> Int {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, let value = Int(text), (1...2000).contains(value) else { throw ValidationError("每杯水量须为 1–2000 ml 的整数") }
        return value
    }
}
