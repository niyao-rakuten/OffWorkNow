import Foundation
import Testing
@testable import WorkdayCore

@Suite("Editable report checklists")
struct DailyReportEditingTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private var date: Date { ISO8601DateFormatter().date(from: "2026-10-19T10:00:00Z")! }
    private func report(items: [BotTodo]) -> DailyReport {
        var settings = WorkSettings(); settings.timeZoneID = calendar.timeZone.identifier
        return DailyReport.snapshot(now: date, settings: settings, checkout: CheckoutRecord(now: date, settings: settings),
            hydration: HydrationSummary(cups: 3, totalML: 1500), checklistItems: items)
    }

    @Test func archiveEditsSurviveRestartWithoutChangingFinancialSnapshotOrIdentity() throws {
        var item = BotTodo(text: "Review PR", due: date)
        item.originID = UUID(); item.delivered = true
        let before = report(items: [item, BotTodo(text: "Other task")])
        var archive = DailyReportArchive(); try archive.upsert(before)
        #expect(try archive.editChecklistItem(reportID: before.id, itemID: item.id, text: "  Updated review  ", done: true))
        let restored = try DailyReportArchive.decode(JSONEncoder().encode(archive))
        let saved = try #require(restored.records.first)
        let edited = try #require(saved.checklistItems?.first)
        #expect(edited.text == "Updated review" && edited.done)
        #expect(edited.id == item.id && edited.originID == item.originID)
        #expect(edited.due == item.due && edited.delivered)
        #expect(saved.updatedAt == before.updatedAt)
        #expect(saved.earned == before.earned && saved.overtimeSeconds == before.overtimeSeconds)
        #expect(saved.checkedOutAt == before.checkedOutAt && saved.waterML == before.waterML)
        #expect(saved.checklistItems?.last == before.checklistItems?.last)
        #expect(try archive.editChecklistItem(reportID: before.id, itemID: item.id, done: false))
        #expect(archive.records.first?.checklistItems?.first?.done == false)
    }

    @Test func emptyEditsAndUnknownIDsCannotDamageArchive() throws {
        let item = BotTodo(text: "Keep me")
        let original = report(items: [item])
        var archive = DailyReportArchive(); try archive.upsert(original)
        #expect(throws: ValidationError.self) {
            try archive.editChecklistItem(reportID: original.id, itemID: item.id, text: " \n ")
        }
        #expect(archive.records == [original])
        #expect(try !archive.editChecklistItem(reportID: original.id, itemID: UUID(), done: true))
        #expect(try !archive.editChecklistItem(reportID: "missing", itemID: item.id, text: "Lost"))
        #expect(archive.records == [original])
    }

    @Test func sourceEditsUpdateRecalledListsButNotIndependentNextDayCopies() throws {
        let item = BotTodo(text: "Review PR")
        var source = AssistantMessage(role: .assistant, content: "Tasks", date: date)
        source.checklist = BotChecklist(items: [item])
        var recalled = AssistantMessage(role: .assistant, content: "Recalled", date: date)
        recalled.checklist = source.checklist
        var tomorrow = AssistantMessage(role: .assistant, content: "New day", date: date.addingTimeInterval(86400))
        var copied = BotTodo(text: item.text); copied.originID = item.id
        tomorrow.checklist = BotChecklist(items: [copied])
        var messages = [source, recalled, tomorrow]
        #expect(try AssistantHistory.editChecklistItem(&messages, itemID: item.id, on: date,
            calendar: calendar, text: "Renamed review", done: true))
        #expect(messages[0].checklist == messages[1].checklist)
        #expect(messages[0].checklist?.items.first?.text == "Renamed review")
        #expect(messages[0].checklist?.items.first?.done == true)
        #expect(messages[2].checklist?.items.first == copied)
        #expect(AssistantHistory.carryoverOffer(Array(messages.prefix(2)), now: tomorrow.date, calendar: calendar) == nil)
        #expect(try !AssistantHistory.editChecklistItem(&messages, itemID: item.id, on: tomorrow.date,
            calendar: calendar, done: false))
    }

    @Test func archiveCanBeEditedWhenOriginalConversationIsMissing() throws {
        let item = BotTodo(text: "Archived task")
        let original = report(items: [item])
        var messages: [AssistantMessage] = []
        #expect(try !AssistantHistory.editChecklistItem(&messages, itemID: item.id, on: date, calendar: calendar, done: true))
        var archive = DailyReportArchive(); try archive.upsert(original)
        #expect(try archive.editChecklistItem(reportID: original.id, itemID: item.id, done: true))
        #expect(archive.records.first?.checklistItems?.first?.done == true)
        #expect(messages.isEmpty)
    }
}
