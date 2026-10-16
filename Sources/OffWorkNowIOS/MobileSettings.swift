import SwiftUI
import WorkdayCore

struct MobileSettings: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: MobileModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkSettings
    @State private var salary: String
    @State private var days: String
    @State private var overtimeGap: String
    @State private var flexibleDate = Date()
    @State private var flexibleMinute: Int
    @State private var cupVolume: String
    @State private var daily: String
    @State private var error: String?
    @State private var overrideDate = Date()
    @State private var overrideWork = false
    @State private var importedAssets: Set<UUID> = []
    init(model: MobileModel) {
        self.model = model; _draft = State(initialValue: model.settings)
        _overtimeGap = State(initialValue: String(model.settings.overtimeIntervalMinutes))
        _flexibleMinute = State(initialValue: model.settings.startMinute(on: model.now))
        _cupVolume = State(initialValue: String(model.settings.cupVolumeML))
        _salary = State(initialValue: Money.input(model.settings.monthlySalary)); _days = State(initialValue: Money.input(model.settings.fixedDays)); _daily = State(initialValue: Money.input(model.settings.customDaily))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("语言")) { AppLanguagePicker() }
                Section(L10n.text("工作安排")) {
                    Picker(L10n.text("工作时区"), selection: $draft.timeZoneID) { ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) } }
                    ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                        Toggle([1:L10n.text("周日"),2:L10n.text("周一"),3:L10n.text("周二"),4:L10n.text("周三"),5:L10n.text("周四"),6:L10n.text("周五"),7:L10n.text("周六")][day]!, isOn: Binding(get: { draft.weekdays.contains(day) }, set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } }))
                    }
                }
                Section(L10n.text("弹性上班")) {
                    timePicker(L10n.text("默认上班"), minute: $draft.startMinute)
                    Stepper(L10n.format("班次时长（含午休） {0}", String(describing: ScheduleCalculator.timeLabel(draft.workDurationMinutes))), value: $draft.workDurationMinutes, in: 1...1439, step: 15)
                    Toggle(L10n.text("不计薪午休"), isOn: $draft.lunchEnabled)
                    if draft.lunchEnabled { timePicker(L10n.text("午休开始"), minute: $draft.lunchStart); timePicker(L10n.text("午休结束"), minute: $draft.lunchEnd) }
                    DatePicker(L10n.text("日期"), selection: $flexibleDate, displayedComponents: .date).environment(\.timeZone, draft.calendar.timeZone)
                    timePicker(L10n.text("当天上班"), minute: $flexibleMinute)
                    Button(L10n.text("添加 / 更新")) { draft.dailyStartMinutes[ScheduleCalculator.key(flexibleDate, calendar: draft.calendar)] = flexibleMinute }
                    ForEach(draft.dailyStartMinutes.keys.sorted(), id: \.self) { key in
                        HStack { Text(key); Text(ScheduleCalculator.timeLabel(draft.dailyStartMinutes[key]!)); Spacer(); Button(L10n.text("使用默认")) { draft.dailyStartMinutes.removeValue(forKey: key) } }
                    }
                    Text(L10n.text("下班时间 = 当天上班 + 班次时长。午休只扣重叠部分，倒计时继续。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("日期覆盖")) {
                    DatePicker(L10n.text("日期"), selection: $overrideDate, displayedComponents: .date).environment(\.timeZone, draft.calendar.timeZone)
                    Toggle(L10n.text("此日工作"), isOn: $overrideWork)
                    Button(L10n.text("添加 / 更新")) { draft.overrides[ScheduleCalculator.key(overrideDate, calendar: draft.calendar)] = overrideWork }
                    ForEach(draft.overrides.keys.sorted(), id: \.self) { key in
                        HStack { Text(key); Spacer(); Text(draft.overrides[key] == true ? L10n.text("工作") : L10n.text("休息")); Button(role: .destructive) { draft.overrides.removeValue(forKey: key) } label: { Image(systemName: "trash") } }
                    }
                }
                HolidayImportSection(overrides: $draft.overrides, calendar: draft.calendar)
                Section(L10n.text("工资估算")) {
                    TextField(L10n.text("月薪（可留空）"), text: $salary).keyboardType(.decimalPad)
                    Picker(L10n.text("折算方式"), selection: $draft.payMode) { ForEach(PayMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    if draft.payMode == .fixedDays { TextField(L10n.text("计薪天数 1–31"), text: $days).keyboardType(.decimalPad) }
                    if draft.payMode == .customDaily { TextField(L10n.text("日薪"), text: $daily).keyboardType(.decimalPad) }
                    Toggle(L10n.text("隐藏工资"), isOn: $draft.hideEarnings)
                    Text(L10n.text("保存后重算今日计划收入。未同步到其他设备，不计加班工资。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("喝水打卡")) {
                    TextField(L10n.text("每杯水量（ml）"), text: $cupVolume).keyboardType(.numberPad)
                    Text(L10n.text("1–2000 ml 的整数，每次记录一杯；修改杯量不改变已有记录。不规定每日饮水目标。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("精灵与提醒")) {
                    Picker(L10n.text("精灵"), selection: $draft.petKind) { ForEach(PetKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle(L10n.text("下班系统通知"), isOn: $draft.offworkEnabled)
                    Toggle(L10n.text("通知声音"), isOn: $draft.notificationSound)
                    Toggle(L10n.text("应用内加班文案"), isOn: $draft.overtimeEnabled)
                    TextField(L10n.text("提示间隔（分钟，默认 5）"), text: $overtimeGap).keyboardType(.numberPad)
                    Text(L10n.text("iOS 预约未来 7 天的下班通知，每次打开重新计划。加班文案在应用内展示，不在后台运行精灵或每 5 分钟唤醒。")).font(.caption).foregroundStyle(.secondary)
                }
                CustomPetEditor(settings: $draft, onImport: { importedAssets.insert($0) })
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(L10n.text("设置"))
            .onChange(of: flexibleDate) { date in
                flexibleMinute = draft.startMinute(on: date)
            }
            .onDisappear { CustomPetLibrary.discard(importedAssets, keeping: model.settings.customPet?.assetID) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.text("保存"), action: save) }
            }
        }
    }
    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        DatePicker(label, selection: Binding(get: {
            let anchor = draft.calendar.date(from: DateComponents(year: 2001, month: 1, day: 15))!
            return ScheduleCalculator.localTime(minute.wrappedValue, on: anchor, calendar: draft.calendar)
        }, set: { minute.wrappedValue = draft.calendar.component(.hour, from: $0) * 60 + draft.calendar.component(.minute, from: $0) }), displayedComponents: .hourAndMinute).environment(\.timeZone, draft.calendar.timeZone).environment(\.calendar, draft.calendar)
    }
    private func save() {
        do {
            var value = draft; value.overtimeIntervalMinutes = try OvertimeCalculator.parseInterval(overtimeGap); value.cupVolumeML = try HydrationCalculator.parseCupVolume(cupVolume); value.monthlySalary = try Money.parse(salary); value.customDaily = try Money.parse(daily)
            guard let fixed = try Money.parse(days, maximum: 31), fixed >= 1 else { throw ValidationError(L10n.text("计薪天数须为 1–31")) }
            value.fixedDays = fixed; try model.save(value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
