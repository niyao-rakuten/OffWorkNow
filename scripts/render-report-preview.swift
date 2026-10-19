import SwiftUI
import AppKit
import WorkdayCore

@main struct ReportPreviewTool {
    @MainActor static func main() throws {
        if CommandLine.arguments.count > 2,
           let language = AppLanguage(rawValue: CommandLine.arguments[2]) {
            UserDefaults.standard.setVolatileDomain([L10n.preferenceKey: language.rawValue],
                forName: UserDefaults.argumentDomain)
        }
        _ = NSApplication.shared
        PetArtwork.resourceDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/PetArt")
        let suite = "OffWorkNow.ReportPreview." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WorkSettings(); settings.timeZoneID = "Asia/Shanghai"; settings.monthlySalary = 21750
        let store = DailyReportStore(defaults: defaults)
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd HH:mm:ss"; format.timeZone = settings.calendar.timeZone
        for day in 1...13 {
            let time = day % 3 == 0 ? "18:42:00" : day % 3 == 1 ? "18:08:00" : "18:21:00"
            let date = format.date(from: String(format: "2026-10-%02d ", day) + time)!
            let checkout = CheckoutRecord(now: date, settings: settings)
            var done = BotTodo(text: "Homepage i18n empty hint & image generation hint"); done.done = true
            let tasks = [done, BotTodo(text: "跟进 Apple 证书过期问题"), BotTodo(text: "优化弹窗交互与背景透明度")]
            store.capture(now: date, settings: settings, checkout: checkout, hydration: HydrationSummary(cups: day % 5 + 1, totalML: (day % 5 + 1) * 500), checklistItems: tasks, force: true)
        }
        let original = store.archive.records.last!
        let editable = original.checklistItems!.last!
        var source = AssistantMessage(role: .assistant, content: "Tasks", date: original.updatedAt)
        source.checklist = BotChecklist(items: original.checklistItems!)
        var history = [source]
        store.onChecklistEdit = { report, itemID, text, done in
            (try? AssistantHistory.editChecklistItem(&history, itemID: itemID, on: report.updatedAt,
                calendar: settings.calendar, text: text, done: done)) == true
        }
        guard store.editChecklistItem(reportID: original.id, itemID: editable.id, done: true),
              store.editChecklistItem(reportID: original.id, itemID: editable.id, text: "已优化弹窗交互与背景透明度") else {
            fatalError("Report checklist edit failed")
        }
        let sourceItems = AssistantHistory.checklistItems(history, on: original.updatedAt, calendar: settings.calendar)
        guard sourceItems.last?.done == true, sourceItems.last?.text == "已优化弹窗交互与背景透明度" else {
            fatalError("Report edit did not reach its source checklist")
        }
        let edited = store.archive
        store.onChecklistEdit = { _, _, _, _ in false }
        guard !store.editChecklistItem(reportID: original.id, itemID: editable.id, done: false),
              store.archive == edited else { fatalError("Rejected source save changed the archive") }
        store.onChecklistEdit = nil
        let restored = DailyReportStore(defaults: defaults)
        guard restored.archive == store.archive, restored.archive.records.count == 13 else { fatalError("Report restart persistence failed") }
        for index in 0..<7 { guard PetArtwork.reportIcon(index) != nil else { fatalError("Missing report icon") } }
        let now = format.date(from: "2026-10-13 18:08:00")!
        let renderer = ImageRenderer(content: DailyReportsView(store: restored, settings: settings, now: now).pageContent.frame(width: 720))
        renderer.scale = 1.5
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("Report render failed") }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/assets/daily-report.png"))
        let damaged = Data("not a report".utf8)
        defaults.set(damaged, forKey: "dailyReportArchive")
        let unreadable = DailyReportStore(defaults: defaults)
        unreadable.capture(now: now, settings: settings, checkout: nil, hydration: HydrationSummary(cups: 0, totalML: 0), force: true)
        guard unreadable.issue != nil, defaults.data(forKey: "dailyReportArchive") == damaged else { fatalError("Corrupt archive must remain untouched") }
        print("PASS: 13 daily records restored, seven icons loaded, task edits persisted and rejected source writes preserved the archive, actual SwiftUI report rendered, corrupted data preserved. Preview uses synthetic data only.")
    }
}
