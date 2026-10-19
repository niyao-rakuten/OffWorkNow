import Foundation

public struct ChecklistCarryover: Codable, Equatable, Sendable {
    public let sourceDate: Date
    public let items: [BotTodo]
    public var accepted: Bool?
    public func prompt(language: AppLanguage) -> String {
        let list = items.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        let question = L10n.format("昨日有未完成的任务：\n{0}\n是否需要创建待办事项？", list, language: language)
        guard let accepted else { return question }
        return question + "\n" + L10n.text(accepted ? "已选择：是" : "已选择：否", language: language)
    }
}
extension AssistantHistory {
    public static func carryoverOffer(_ messages: [AssistantMessage], now: Date, calendar: Calendar) -> ChecklistCarryover? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        let items = checklistItems(messages, on: yesterday, calendar: calendar).filter { !$0.done && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return items.isEmpty ? nil : ChecklistCarryover(sourceDate: yesterday, items: items)
    }
    /// Persist the decision and the new checklist together. Repeated clicks have no effect.
    @discardableResult public static func answerCarryover(_ messages: inout [AssistantMessage], messageID: UUID, accept: Bool, now: Date, calendar: Calendar) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let offer = messages[index].carryover, offer.accepted == nil,
              calendar.isDate(messages[index].date, inSameDayAs: now) else { return false }
        messages[index].carryover?.accepted = accept
        guard accept else { return true }
        let pending = checklistItems(messages, on: offer.sourceDate, calendar: calendar).filter { !$0.done }
        let offeredIDs = Set(offer.items.map(\.id))
        let existing = Set(checklistItems(messages, on: now, calendar: calendar).map { $0.originID ?? $0.id })
        let items = pending.filter { offeredIDs.contains($0.id) && !existing.contains($0.originID ?? $0.id) }.map { original in
            var copy = BotTodo(text: original.text)
            copy.originID = original.originID ?? original.id
            return copy
        }
        var reply = AssistantMessage(role: .assistant, content: "", date: now)
        let key = items.isEmpty ? "昨日任务已完成或已加入今日待办，无需重复创建。" : "已将昨日未完成事项加入今日待办。"
        reply.localizedContents = Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map { ($0.rawValue, L10n.text(key, language: $0)) })
        reply.content = reply.localizedContents?[L10n.selection.resolved().rawValue] ?? ""
        if !items.isEmpty { reply.checklist = BotChecklist(items: items) }
        messages.append(reply)
        return true
    }
}
