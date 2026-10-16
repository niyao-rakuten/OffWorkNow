import Foundation
import Combine
import WorkdayCore

@MainActor final class DailyReportStore: ObservableObject {
    @Published private(set) var archive = DailyReportArchive()
    @Published private(set) var issue: String?
    private let defaults: UserDefaults
    private var lastMinute: Int?
    private var lastDay: String?
    private var readable = true
    #if DEBUG
    private var debugClearedDays: Set<String> = []
    func debugClear(dateKey: String, timeZoneID: String) throws {
        guard readable else { throw ValidationError(issue ?? "日报无法读取") }
        var next = archive
        next.debugRemove(dateKey: dateKey, timeZoneID: timeZoneID)
        defaults.set(try JSONEncoder().encode(next), forKey: "dailyReportArchive")
        archive = next
        debugClearedDays.insert(timeZoneID + "/" + dateKey)
    }
    #endif
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "dailyReportArchive") {
            do { archive = try DailyReportArchive.decode(data) }
            catch { readable = false; issue = L10n.text("日报数据无法读取，已保留原始数据，暂不覆盖。") }
        }
    }
    func capture(now: Date, settings: WorkSettings, checkout: CheckoutRecord?, hydration: HydrationSummary, force: Bool = false) {
        guard readable else { return }
        let day = settings.timeZoneID + "/" + ScheduleCalculator.key(now, calendar: settings.calendar)
        #if DEBUG
        if force { debugClearedDays.remove(day) }
        else if debugClearedDays.contains(day) { return }
        #endif
        let minute = Int(now.timeIntervalSince1970 / 60)
        // Minute snapshots plus immediate action snapshots; no per-animation-frame disk writes.
        guard force || minute != lastMinute || day != lastDay else { return }
        let report = AIBot().inspect(AIBotContext(now: now, settings: settings, checkout: checkout, hydration: hydration)).report
        do {
            var next = archive; try next.upsert(report)
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: "dailyReportArchive")
            archive = next; issue = nil; lastMinute = minute; lastDay = day
        } catch { issue = L10n.text("日报保存失败：") + error.localizedDescription }
    }
}
