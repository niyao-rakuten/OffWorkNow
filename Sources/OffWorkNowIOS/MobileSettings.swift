import SwiftUI
import WorkdayCore

struct MobileSettings: View {
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
                Section("工作安排") {
                    Picker("工作时区", selection: $draft.timeZoneID) { ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) } }
                    ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                        Toggle([1:"周日",2:"周一",3:"周二",4:"周三",5:"周四",6:"周五",7:"周六"][day]!, isOn: Binding(get: { draft.weekdays.contains(day) }, set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } }))
                    }
                }
                Section("弹性上班") {
                    timePicker("默认上班", minute: $draft.startMinute)
                    Stepper("班次时长（含午休） \(ScheduleCalculator.timeLabel(draft.workDurationMinutes))", value: $draft.workDurationMinutes, in: 1...1439, step: 15)
                    Toggle("不计薪午休", isOn: $draft.lunchEnabled)
                    if draft.lunchEnabled { timePicker("午休开始", minute: $draft.lunchStart); timePicker("午休结束", minute: $draft.lunchEnd) }
                    DatePicker("日期", selection: $flexibleDate, displayedComponents: .date).environment(\.timeZone, draft.calendar.timeZone)
                    timePicker("当天上班", minute: $flexibleMinute)
                    Button("添加 / 更新") { draft.dailyStartMinutes[ScheduleCalculator.key(flexibleDate, calendar: draft.calendar)] = flexibleMinute }
                    ForEach(draft.dailyStartMinutes.keys.sorted(), id: \.self) { key in
                        HStack { Text(key); Text(ScheduleCalculator.timeLabel(draft.dailyStartMinutes[key]!)); Spacer(); Button("使用默认") { draft.dailyStartMinutes.removeValue(forKey: key) } }
                    }
                    Text("下班时间 = 当天上班 + 班次时长。午休只扣重叠部分，倒计时继续。").font(.caption).foregroundStyle(.secondary)
                }
                Section("日期覆盖") {
                    DatePicker("日期", selection: $overrideDate, displayedComponents: .date).environment(\.timeZone, draft.calendar.timeZone)
                    Toggle("此日工作", isOn: $overrideWork)
                    Button("添加 / 更新") { draft.overrides[ScheduleCalculator.key(overrideDate, calendar: draft.calendar)] = overrideWork }
                    ForEach(draft.overrides.keys.sorted(), id: \.self) { key in
                        HStack { Text(key); Spacer(); Text(draft.overrides[key] == true ? "工作" : "休息"); Button(role: .destructive) { draft.overrides.removeValue(forKey: key) } label: { Image(systemName: "trash") } }
                    }
                }
                Section("工资估算") {
                    TextField("月薪（可留空）", text: $salary).keyboardType(.decimalPad)
                    Picker("折算方式", selection: $draft.payMode) { ForEach(PayMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    if draft.payMode == .fixedDays { TextField("计薪天数 1–31", text: $days).keyboardType(.decimalPad) }
                    if draft.payMode == .customDaily { TextField("日薪", text: $daily).keyboardType(.decimalPad) }
                    Toggle("隐藏工资", isOn: $draft.hideEarnings)
                    Text("保存后重算今日计划收入。未同步到其他设备，不计加班工资。").font(.caption).foregroundStyle(.secondary)
                }
                Section("喝水打卡") {
                    TextField("每杯水量（ml）", text: $cupVolume).keyboardType(.numberPad)
                    Text("1–2000 ml 的整数，每次记录一杯；修改杯量不改变已有记录。不规定每日饮水目标。").font(.caption).foregroundStyle(.secondary)
                }
                Section("伙伴与提醒") {
                    Picker("伙伴", selection: $draft.petKind) { ForEach(PetKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("下班系统通知", isOn: $draft.offworkEnabled)
                    Toggle("通知声音", isOn: $draft.notificationSound)
                    Toggle("应用内加班文案", isOn: $draft.overtimeEnabled)
                    TextField("提示间隔（分钟，默认 5）", text: $overtimeGap).keyboardType(.numberPad)
                    Text("iOS 预约未来 7 天的下班通知，每次打开重新计划。加班文案在应用内展示，不在后台运行宠物或每 5 分钟唤醒。").font(.caption).foregroundStyle(.secondary)
                }
                CustomPetEditor(settings: $draft, onImport: { importedAssets.insert($0) })
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("设置")
            .onChange(of: flexibleDate) { date in
                flexibleMinute = draft.startMinute(on: date)
            }
            .onDisappear { CustomPetLibrary.discard(importedAssets, keeping: model.settings.customPet?.assetID) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
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
            guard let fixed = try Money.parse(days, maximum: 31), fixed >= 1 else { throw ValidationError("计薪天数须为 1–31") }
            value.fixedDays = fixed; try model.save(value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
