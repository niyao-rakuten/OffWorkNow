import SwiftUI
import AppKit
import WorkdayCore

@main struct ReportPreviewTool {
    @MainActor static func main() throws {
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
            store.capture(now: date, settings: settings, checkout: checkout, hydration: HydrationSummary(cups: day % 5 + 1, totalML: (day % 5 + 1) * 500), force: true)
        }
        let restored = DailyReportStore(defaults: defaults)
        guard restored.archive == store.archive, restored.archive.records.count == 13 else { fatalError("Report restart persistence failed") }
        for index in 0..<6 { guard PetArtwork.reportIcon(index) != nil else { fatalError("Missing report icon") } }
        let now = format.date(from: "2026-10-13 18:08:00")!
        let renderer = ImageRenderer(content: DailyReportsView(store: restored, settings: settings, now: now).pageContent.frame(width: 720))
        renderer.scale = 1.5
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("Report render failed") }
        try data.write(to: URL(fileURLWithPath: "docs/assets/daily-report.png"))
        let damaged = Data("not a report".utf8)
        defaults.set(damaged, forKey: "dailyReportArchive")
        let unreadable = DailyReportStore(defaults: defaults)
        unreadable.capture(now: now, settings: settings, checkout: nil, hydration: HydrationSummary(cups: 0, totalML: 0), force: true)
        guard unreadable.issue != nil, defaults.data(forKey: "dailyReportArchive") == damaged else { fatalError("Corrupt archive must remain untouched") }
        print("PASS: 13 daily records restored, six icons loaded, actual SwiftUI report rendered, corrupted data preserved. Preview uses synthetic data only.")
    }
}
