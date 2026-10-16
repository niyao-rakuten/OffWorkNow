import SwiftUI
import WorkdayCore

struct HolidayImportSection: View {
    @Binding var overrides: [String: Bool]
    let calendar: Calendar
    @State private var showingImport = false
    var body: some View {
        Section(L10n.text("法定节假日")) {
            Button(L10n.text("导入放假安排文本")) { showingImport = true }
            Text(L10n.text("粘贴放假通知，预览假期和补班日期后导入。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingImport) {
            HolidayImportView(overrides: $overrides, defaultYear: calendar.component(.year, from: Date()))
        }
    }
}

private struct HolidayImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = AppLanguageStore.shared
    @Binding var overrides: [String: Bool]
    @State private var year: String
    @State private var text = ""
    @State private var result: HolidayImportResult?
    @State private var issue: String?
    init(overrides: Binding<[String: Bool]>, defaultYear: Int) {
        _overrides = overrides
        _year = State(initialValue: String(defaultYear))
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.text("通知所属年份（如 2026）"), text: $year)
                    .textFieldStyle(.roundedBorder)
                Text(L10n.text("放假安排原文")).font(.headline)
                TextEditor(text: $text).frame(height: 160)
                    .border(.secondary.opacity(0.3))
                    .accessibilityLabel(L10n.text("放假安排原文"))
                Button(L10n.text("解析并预览"), action: parse).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let issue { Text(issue).foregroundStyle(.red).font(.callout) }
                if let result {
                    Text(L10n.format("已识别 {0} 个节日，{1} 天放假，{2} 天补班。", String(result.holidays.count), String(result.restCount), String(result.workCount))).font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(result.holidays) { holiday in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(holiday.name).font(.headline)
                                    Text(L10n.format("放假：{0}", holiday.holidays.joined(separator: ", ")))
                                    if !holiday.workdays.isEmpty { Text(L10n.format("补班：{0}", holiday.workdays.joined(separator: ", "))) }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(maxHeight: .infinity)
                } else { Spacer(minLength: 0) }
                Text(L10n.text("只覆盖解析到的日期，其他日期不变。导入到草稿后，点击设置页的保存才会生效。建议性的休息安排不会导入。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("导入到工作安排草稿")) {
                        guard let result else { return }
                        overrides.merge(result.overrides) { _, imported in imported }
                        dismiss()
                    }.buttonStyle(.borderedProminent).disabled(result == nil)
                }
            }.padding(20)
                .navigationTitle(L10n.text("导入法定节假日"))
                .onChange(of: text) { _ in result = nil; issue = nil }
                .onChange(of: year) { _ in result = nil; issue = nil }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 600, idealHeight: 680)
        #endif
    }
    private func parse() {
        result = nil; issue = nil
        do {
            guard let year = Int(year.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ValidationError(L10n.text("请输入有效的四位年份。"))
            }
            result = try AIBot().importHolidayNotice(text, year: year)
        } catch { issue = error.localizedDescription }
    }
}
