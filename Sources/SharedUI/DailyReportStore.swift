import Foundation
import Combine
import WorkdayCore

@MainActor final class DailyReportStore: ObservableObject {
    @Published private(set) var archive = DailyReportArchive()
    @Published private(set) var issue: String?
    var onChecklistEdit: ((DailyReport, UUID, String?, Bool?) -> Bool)?
    private let defaults: UserDefaults
    private var lastMinute: Int?
    private var lastDay: String?
    private var lastChecklistItems: [BotTodo] = []
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
    @discardableResult func editChecklistItem(reportID: String, itemID: UUID,
        text: String? = nil, done: Bool? = nil) -> Bool {
        guard readable, let report = archive.records.first(where: { $0.id == reportID }) else { return false }
        do {
            var next = archive
            guard try next.editChecklistItem(reportID: reportID, itemID: itemID, text: text, done: done) else { return false }
            let data = try JSONEncoder().encode(next)
            if let onChecklistEdit, !onChecklistEdit(report, itemID, text, done) {
                issue = L10n.text("待办保存失败，请重试。")
                return false
            }
            defaults.set(data, forKey: "dailyReportArchive")
            archive = next; issue = nil
            return true
        } catch { issue = error.localizedDescription; return false }
    }
    func capture(now: Date, settings: WorkSettings, checkout: CheckoutRecord?, hydration: HydrationSummary, checklistItems: [BotTodo] = [], force: Bool = false) {
        guard readable else { return }
        let day = settings.timeZoneID + "/" + ScheduleCalculator.key(now, calendar: settings.calendar)
        #if DEBUG
        if force { debugClearedDays.remove(day) }
        else if debugClearedDays.contains(day) { return }
        #endif
        let minute = Int(now.timeIntervalSince1970 / 60)
        // Minute snapshots plus immediate action snapshots; no per-animation-frame disk writes.
        guard force || minute != lastMinute || day != lastDay || checklistItems != lastChecklistItems else { return }
        let report = AIBot().inspect(AIBotContext(now: now, settings: settings, checkout: checkout, hydration: hydration, checklistItems: checklistItems)).report
        do {
            var next = archive; try next.upsert(report)
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: "dailyReportArchive")
            archive = next; issue = nil; lastMinute = minute; lastDay = day; lastChecklistItems = checklistItems
        } catch { issue = L10n.text("日报保存失败：") + error.localizedDescription }
    }
}
