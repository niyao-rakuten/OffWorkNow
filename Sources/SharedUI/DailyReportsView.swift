import SwiftUI
import Charts
import WorkdayCore

private enum DiaryStyle {
    static let ink = Color(red: 0.30, green: 0.23, blue: 0.20)
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    static let accent = Color(red: 0.72, green: 0.40, blue: 0.28)
}

struct ReportIcon: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let index: Int
    var body: some View {
        if let image = PetArtwork.reportIcon(index) {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
        }
    }
}

struct DailyReportsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: DailyReportStore
    let settings: WorkSettings
    let now: Date
    @State private var monthOffset = 0
    @State private var selectedKey: String?
    @State private var metric = Metric.water

    private enum Metric: String, CaseIterable {
        case water = "喝水", income = "收入", overtime = "加班"
        var unit: String { switch self { case .water: return "ml"; case .income: return L10n.text("元"); case .overtime: return L10n.text("分钟") } }
    }
    private var calendar: Calendar { settings.calendar }
    private var month: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: calendar.dateInterval(of: .month, for: now)!.start)!
    }
    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: month)
    }
    private var prefix: String { String(ScheduleCalculator.key(month, calendar: calendar).prefix(7)) }
    private var records: [DailyReport] {
        store.archive.records.filter { $0.timeZoneID == settings.timeZoneID && $0.dateKey.hasPrefix(prefix) }.sorted { $0.dateKey < $1.dateKey }
    }
    private var selected: DailyReport? {
        let key = selectedKey ?? (monthOffset == 0 ? ScheduleCalculator.key(now, calendar: calendar) : records.last?.dateKey)
        return records.first { $0.dateKey == key }
    }
    private var days: [Date?] {
        let padding = (calendar.component(.weekday, from: month) + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        return Array(repeating: nil, count: padding) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: month) }
    }
    var body: some View {
        ScrollView { pageContent }
        .environment(\.colorScheme, .light)
        .background(DiaryStyle.paper).foregroundStyle(DiaryStyle.ink).tint(DiaryStyle.accent)
        .onChange(of: settings.timeZoneID) { _ in monthOffset = 0; selectedKey = nil }
    }
    // Share the actual page content with the offscreen rendering tool.
    var pageContent: some View {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    PetAvatar(kind: .fox, animate: false).frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("下班啦 · 收工日记")).font(.system(size: 25, weight: .bold, design: .rounded))
                        Text(L10n.text("把努力记下来，也把自己照顾好。")).font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                calendarCard
                if let selected { reportCard(selected) }
                else { Text(L10n.text("这一天还没有记录，未来的每一次喝水和收工都会留在这里。"))
                    .font(.subheadline).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18)) }
                chartCard
                if let issue = store.issue { Text(issue).font(.caption).foregroundStyle(.red) }
                Text(L10n.format("记录仅保存在本机 · 工作时区 {0}\n收入为按工作安排估算，打卡后冻结日报收入；不代表实际到账。未打卡的加班时长记录到应用最后运行时刻。缺失日期不补零。", String(describing: settings.timeZoneID)))
                    .font(.caption).foregroundStyle(DiaryStyle.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .light)
        .background(DiaryStyle.paper).foregroundStyle(DiaryStyle.ink).tint(DiaryStyle.accent)
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { monthOffset -= 1; selectedKey = nil } label: { Image(systemName: "chevron.left") }.accessibilityLabel(L10n.text("上个月"))
                Spacer(); Text(monthLabel).font(.title3.bold()); Spacer()
                Button { monthOffset += 1; selectedKey = nil } label: { Image(systemName: "chevron.right") }.accessibilityLabel(L10n.text("下个月"))
                Button(L10n.text("今天")) { monthOffset = 0; selectedKey = nil }.font(.caption)
            }.buttonStyle(.plain)
            HStack { ForEach([L10n.text("一"), L10n.text("二"), L10n.text("三"), L10n.text("四"), L10n.text("五"), L10n.text("六"), L10n.text("日")], id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] { calendarDay(date) }
                    else { Color.clear.frame(height: 63).accessibilityHidden(true) }
                }
            }
            HStack(spacing: 12) {
                ForEach([ReportMood.happy, .neutral, .crying], id: \.rawValue) { mood in
                    HStack(spacing: 3) { ReportIcon(index: mood.rawValue).frame(width: 24, height: 24); Text(mood == .happy ? L10n.text("<15分") : mood == .neutral ? L10n.text("15–30分") : L10n.text("≥30分")).font(.caption2) }
                }
                Spacer(minLength: 0)
            }
        }.padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
    }
    private func calendarDay(_ date: Date) -> some View {
        let key = ScheduleCalculator.key(date, calendar: calendar)
        let record = records.first { $0.dateKey == key }
        let activeKey = selectedKey ?? (monthOffset == 0 ? ScheduleCalculator.key(now, calendar: calendar) : records.last?.dateKey)
        return Button { selectedKey = key } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))").font(.system(size: 12, weight: .semibold, design: .rounded))
                if let mood = record?.mood { ReportIcon(index: mood.rawValue).frame(width: 30, height: 28) }
                else { Text(record == nil ? "·" : record?.isWorkday == false ? L10n.text("休") : L10n.text("进行中")).font(.system(size: 9)).frame(height: 28) }
            }
            .frame(maxWidth: .infinity).frame(height: 63)
            .background(key == activeKey ? Color(red: 0.96, green: 0.85, blue: 0.71) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(key + "，" + (record?.mood?.title ?? (record == nil ? L10n.text("未记录") : L10n.text("尚无收工结果"))))
    }
    private func reportCard(_ report: DailyReport) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(report.dateKey + L10n.text(" · 每日报表")).font(.headline)
                Spacer()
                Text(report.checkedOutAt != nil ? L10n.text("已打卡") : report.isWorkday ? L10n.text("未打卡") : L10n.text("休息日")).font(.caption)
            }
            reportRow(icon: 3, title: L10n.format("喝水 {0} ml · {1} 杯", String(describing: report.waterML), String(describing: report.cups)), message: report.waterMessage)
            Divider().overlay(DiaryStyle.ink.opacity(0.12))
            reportRow(icon: 4, title: L10n.text("今日收入 ") + (settings.hideEarnings ? "¥••••" : report.earned.map(Money.formatted) ?? L10n.text("待设置")),
                      message: settings.hideEarnings ? L10n.text("辛苦啦～收入已隐藏，快乐下班～") : report.salaryMessage)
            Divider().overlay(DiaryStyle.ink.opacity(0.12))
            reportRow(icon: 5, title: L10n.text("加班 ") + OvertimeCalculator.duration(report.overtimeSeconds), message: report.overtimeMessage)
        }.padding(20).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
    }
    private func reportRow(icon: Int, title: String, message: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ReportIcon(index: icon).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("这个月的小轨迹")).font(.headline)
            HStack(spacing: 8) {
                ForEach(Metric.allCases, id: \.self) { item in
                    Button { metric = item } label: {
                        Text(L10n.text(item.rawValue)).font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(item == metric ? DiaryStyle.accent.opacity(0.18) : .white.opacity(0.7), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(item == metric ? .isSelected : [])
                }
            }.accessibilityElement(children: .contain).accessibilityLabel(L10n.text("统计指标"))
            if metric == .income && settings.hideEarnings { Text(L10n.text("收入已隐藏，图表同步隐藏。")).font(.subheadline).frame(height: 180) }
            else if records.isEmpty { Text(L10n.text("记录几天后，就能看到自己的变化啦。")).font(.subheadline).frame(height: 180) }
            else {
                Chart(records) { report in
                    if let value = chartValue(report), let date = ScheduleCalculator.date(from: report.dateKey, calendar: calendar) {
                        LineMark(x: .value(L10n.text("日期"), date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(DiaryStyle.accent)
                        PointMark(x: .value(L10n.text("日期"), date, unit: .day), y: .value(metric.unit, value)).foregroundStyle(DiaryStyle.accent)
                            .accessibilityLabel(report.dateKey).accessibilityValue("\(value.formatted()) \(metric.unit)")
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day()) } }
                .chartYAxisLabel(metric.unit).frame(height: 180)
                .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            }
            Text(L10n.text("点击日历查看具体日期；只显示已记录数据，收入未设置的日期不绘制收入点。")).font(.caption).foregroundStyle(DiaryStyle.ink.opacity(0.7))
        }.padding(20).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
    }
    private func chartValue(_ report: DailyReport) -> Double? {
        switch metric {
        case .water: return Double(report.waterML)
        case .income: return report.earned.map { NSDecimalNumber(decimal: $0).doubleValue }
        case .overtime: return report.overtimeSeconds / 60
        }
    }
}
