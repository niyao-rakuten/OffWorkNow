import SwiftUI
import AppKit
import WorkdayCore

#if DEBUG
private struct DebugDailyDataView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var assistant: AssistantStore
    @State private var taps = 0
    @State private var lastTap: Date?
    @State private var unlocked = false
    @State private var date = Date()
    @State private var confirmClear = false
    @State private var status: String?
    private var dateKey: String { ScheduleCalculator.key(date, calendar: model.settings.calendar) }
    var body: some View {
        Section {
            Button(L10n.text("工作安排")) {
                let now = Date()
                taps = lastTap.map { now.timeIntervalSince($0) <= 1.5 } == true ? taps + 1 : 1
                lastTap = now
                if taps >= 7 { unlocked = true }
            }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            if unlocked {
                Text("DEBUG · 清除指定日期数据").font(.headline)
                DatePicker("日期（已保存的工作时区）", selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, model.settings.calendar.timeZone)
                    .environment(\.calendar, model.settings.calendar)
                Text("时区：\(model.settings.timeZoneID)\n清除打卡、饮水、日报、提醒记录和该日聊天消息。保留工作安排和薪资设置。清除今天后，可重新打卡测试日报。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("清除 \(dateKey) 的数据", role: .destructive) { confirmClear = true }
                    .disabled(assistant.isStreaming)
                if assistant.isStreaming { Text("请先停止 AI 回复，再清除数据。").font(.caption) }
                if let status { Text(status).font(.caption).textSelection(.enabled) }
            }
        }
        .alert("清除 \(dateKey) 的数据？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                do { try model.debugClearData(on: date); status = "已清除 \(dateKey) 的数据。" }
                catch { status = "清除失败：\(error.localizedDescription)" }
            }
        } message: {
            Text("工作时区：\(model.settings.timeZoneID)。此操作立即生效，无法撤销。")
        }
    }
}
#endif

struct SettingsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var draft: WorkSettings
    @State private var monthly: String
    @State private var daily: String
    @State private var overtimeGap: String
    @State private var flexibleDate = Date()
    @State private var flexibleTime: String
    @State private var cupVolume: String
    @State private var days: String
    @State private var start: String
    @State private var duration: String
    @State private var syncedDailyStarts: [String: Int]
    @State private var lunchStart: String
    @State private var lunchEnd: String
    @State private var launchAtLogin: Bool
    @State private var errors: [String: String] = [:]
    @State private var confirmReset = false
    @State private var importedAssets: Set<UUID> = []
    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        let s = model.settings
        _draft = State(initialValue: s); _monthly = State(initialValue: Money.input(s.monthlySalary)); _daily = State(initialValue: Money.input(s.customDaily)); _days = State(initialValue: Money.input(s.fixedDays))
        _overtimeGap = State(initialValue: String(s.overtimeIntervalMinutes))
        _flexibleTime = State(initialValue: ScheduleCalculator.timeLabel(s.startMinute(on: model.now)))
        _cupVolume = State(initialValue: String(s.cupVolumeML))
        _start = State(initialValue: ScheduleCalculator.timeLabel(s.startMinute)); _duration = State(initialValue: ScheduleCalculator.timeLabel(s.workDurationMinutes)); _syncedDailyStarts = State(initialValue: s.dailyStartMinutes)
        _lunchStart = State(initialValue: ScheduleCalculator.timeLabel(s.lunchStart)); _lunchEnd = State(initialValue: ScheduleCalculator.timeLabel(s.lunchEnd)); _launchAtLogin = State(initialValue: model.login.enabled)
    }
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.selectedSettingsTab) {
                scheduleTab.tabItem { Label(L10n.text("工作安排"), systemImage: "calendar") }.tag("schedule")
                payTab.tabItem { Label(L10n.text("工资"), systemImage: "yensign.circle") }.tag("pay")
                remindersTab.tabItem { Label(L10n.text("提醒"), systemImage: "bell") }.tag("reminders")
                AssistantSettingsView(store: model.assistant).tabItem { Label(L10n.text("AI 助手"), systemImage: "bubble.left.and.bubble.right") }.tag("assistant")
                generalTab.tabItem { Label(L10n.text("通用"), systemImage: "gearshape") }.tag("general")
            }.padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if !errors.isEmpty { Text(errors.keys.sorted().compactMap { errors[$0] }.joined(separator: "\n")).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityLabel(L10n.text("保存失败，") + errors.values.joined(separator: "，")) }
                HStack {
                    Text(L10n.text("保存后立即重算当天估算，不记录分段薪资。")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("取消"), action: close).keyboardShortcut(.cancelAction)
                    Button(L10n.text("保存"), action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }.padding(16)
        }.frame(minWidth: 560, minHeight: 500)
        .onChange(of: model.settings.dailyStartMinutes) { newValue in
            for key in Set(syncedDailyStarts.keys).union(newValue.keys) {
                if newValue[key] != syncedDailyStarts[key] {
                    draft.dailyStartMinutes[key] = newValue[key]
                }
            }
            syncedDailyStarts = newValue
            flexibleTime = ScheduleCalculator.timeLabel(draft.startMinute(on: flexibleDate))
        }
        .onChange(of: flexibleDate) { date in
            flexibleTime = ScheduleCalculator.timeLabel(draft.startMinute(on: date))
        }
        .onDisappear { CustomPetLibrary.discard(importedAssets, keeping: model.settings.customPet?.assetID) }
        .alert(L10n.text("恢复默认设置？"), isPresented: $confirmReset) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("恢复默认草稿"), role: .destructive, action: reset)
        } message: { Text(L10n.text("将清除草稿中的月薪、日期覆盖和提醒偏好，并关闭开机启动。点击保存后生效，不改变系统通知授权。")) }
    }
    private var scheduleTab: some View {
        NavigationStack { scheduleForm }
    }
    private var scheduleForm: some View {
        Form {
            Section(L10n.text("工作时区")) {
                Picker(L10n.text("时区"), selection: $draft.timeZoneID) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                if draft.timeZoneID != TimeZone.current.identifier { Text(L10n.format("与系统时区 {0} 不同；显示和提醒均使用工作时区。", String(describing: TimeZone.current.identifier))).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L10n.text("常规工作日")) {
                HStack {
                    ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                        Toggle(dayName(day), isOn: Binding(get: { draft.weekdays.contains(day) }, set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } })).toggleStyle(.checkbox)
                    }
                }
                Text(L10n.text("可导入法定节假日通知，或手动添加日期覆盖。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("弹性上班 · 每天可不同")) {
                timeField(L10n.text("默认上班（HH:mm）"), value: $start, errorKey: "start")
                timeField(L10n.text("班次时长（HH:mm，含午休）"), value: $duration, errorKey: "duration")
                Toggle(L10n.text("启用不计薪午休"), isOn: $draft.lunchEnabled)
                if draft.lunchEnabled { timeField(L10n.text("午休开始"), value: $lunchStart, errorKey: "lunchStart"); timeField(L10n.text("午休结束"), value: $lunchEnd, errorKey: "lunchEnd") }
                Text(L10n.text("下班时间 = 当天上班 + 班次时长；午休工资和进度暂停，倒计时继续。")).font(.caption).foregroundStyle(.secondary)
                NavigationLink {
                    DailyStartTimesView(starts: $draft.dailyStartMinutes, selectedDate: $flexibleDate,
                        selectedTime: $flexibleTime, calendar: draft.calendar,
                        error: Binding(get: { errors["flexible"] }, set: { errors["flexible"] = $0 }), apply: addDailyStart)
                } label: {
                    HStack {
                        Text(L10n.text("每天的开始时间"))
                        Spacer()
                        Text(L10n.format("{0} 条记录", String(draft.dailyStartMinutes.count))).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.text("指定日期覆盖")) {
                NavigationLink {
                    DateOverridesView(overrides: $draft.overrides, calendar: draft.calendar)
                } label: {
                    HStack {
                        Text(L10n.text("管理日期覆盖"))
                        Spacer()
                        Text(L10n.format("{0} 条记录", String(draft.overrides.count))).foregroundStyle(.secondary)
                    }
                }
            }
            HolidayImportSection(overrides: $draft.overrides, calendar: draft.calendar)
            #if DEBUG
            DebugDailyDataView(model: model, assistant: model.assistant)
            #endif
        }.formStyle(.grouped)
    }
    private var payTab: some View {
        Form {
            Section(L10n.text("工资估算")) {
                moneyField(L10n.text("月薪（元，可留空）"), value: $monthly, errorKey: "monthly")
                Picker(L10n.text("折算方式"), selection: $draft.payMode) { ForEach(PayMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                switch draft.payMode {
                case .fixedDays:
                    moneyField(L10n.text("月计薪天数（1–31）"), value: $days, errorKey: "days")
                    Text(L10n.text("日薪 = 月薪 ÷ 计薪天数。21.75 仅是可修改的估算参数，自然月累计不保证等于月薪。")).font(.caption).foregroundStyle(.secondary)
                case .plannedDays: Text(L10n.text("日薪 = 月薪 ÷ 当月按星期和日期覆盖计算的计划工作日数。")).font(.caption).foregroundStyle(.secondary)
                case .customDaily:
                    moneyField(L10n.text("自定义日薪（元）"), value: $daily, errorKey: "daily")
                    Text(L10n.text("此模式不使用月薪计算，月薪字段仍保留。")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L10n.text("隐藏工资（菜单栏与面板）"), isOn: $draft.hideEarnings)
                Text(L10n.text("收入只按计划工作进度估算，不计加班。金额最多两位小数，可输入规范千位逗号；0 与未设置不同。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("草稿实时预览")) { preview }
        }.formStyle(.grouped)
    }
    private var remindersTab: some View {
        Form {
            Section(L10n.text("整点健康提醒")) {
                Toggle(L10n.text("有效工作时段整点提醒"), isOn: $draft.hourlyEnabled)
                ForEach(ReminderCategory.allCases, id: \.self) { category in
                    Toggle(category.title, isOn: Binding(get: { draft.categories.contains(category) }, set: { if $0 { draft.categories.insert(category) } else { draft.categories.remove(category) } }))
                }
                Text(L10n.text("全部类别关闭时仍报整点。暂停只影响整点，不影响下班通知。")).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("通知声音"), isOn: $draft.notificationSound)
                Toggle(L10n.text("中文语音报时"), isOn: $draft.speechEnabled)
                Text(L10n.text("语音独立于通知权限；通知关闭但语音开启仍可能报时。仅会话确认未锁定且未睡眠时播放。")).font(.caption).foregroundStyle(.secondary)
                Text(model.speech.statusText).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("下班通知（每天一次）"), isOn: $draft.offworkEnabled)
                Toggle(L10n.text("启用加班提醒"), isOn: $draft.overtimeEnabled)
                TextField(L10n.text("加班提示间隔（分钟）"), text: $overtimeGap).monospacedDigit()
                if let error = errors["overtimeGap"] { Text(error).font(.caption).foregroundStyle(.red) }
                Text(L10n.text("到下班时间仍未打卡则开始加班计时；按设定间隔（默认 5 分钟）弹出精灵文案并发送系统通知。点击“打卡下班”停止当天所有提醒，不计算加班工资。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("系统通知")) { NotificationSettingsView(service: model.notifications) }
            Section(L10n.text("测试")) {
                Button(L10n.text("发送测试提醒")) { model.reminders.test(settings: draft) }
                Text(L10n.text("使用当前草稿的提醒偏好与系统权限，不保存设置，也不改变正式提醒计划。")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var generalTab: some View {
        Form {
            Section(L10n.text("语言")) { AppLanguagePicker() }
            Section(L10n.text("菜单栏")) {
                Picker(L10n.text("显示方式"), selection: $draft.menuMode) { ForEach(MenuMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                Text(L10n.text("状态项位置由 macOS 管理；可按住 Command 拖动调整。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("喝水打卡")) {
                TextField(L10n.text("每杯水量（ml）"), text: $cupVolume).monospacedDigit()
                if let error = errors["cupVolume"] { Text(error).font(.caption).foregroundStyle(.red) }
                Text(L10n.text("1–2000 ml 的整数。每次喝水打卡记录一杯，修改杯量不改变已有记录。显示当天杯数与总量，不规定每日饮水目标。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("桌面精灵")) {
                Toggle(L10n.text("显示常驻桌面精灵"), isOn: $draft.petEnabled)
                Picker(L10n.text("选择精灵"), selection: $draft.petKind) { ForEach(PetKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle(L10n.text("精灵置顶"), isOn: $draft.petAlwaysOnTop)
                Picker(L10n.text("消息面板位置"), selection: $draft.chatPanelPosition) {
                    ForEach(ChatPanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                PetAvatar(kind: draft.petKind, custom: draft.customPet).frame(width: 110, height: 110)
                Text(L10n.text("拖动精灵或空白处可移动；支持减少动态效果。隐藏精灵不关闭通知。")).font(.caption).foregroundStyle(.secondary)
            }
            CustomPetEditor(settings: $draft, onImport: { importedAssets.insert($0) })
            Section(L10n.text("开机启动")) {
                Toggle(L10n.text("登录后启动下班啦"), isOn: $launchAtLogin)
                LoginStatusView(service: model.login)
                Text(L10n.text("保存时注册系统服务。建议将已签名 .app 放在固定位置；开发构建和移动路径可能影响注册。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("本地与隐私")) {
                Text(L10n.text("月薪与安排仅保存在本机，不访问网络，不读取日历、位置或屏幕。退出后停止提醒。"))
                Button(L10n.text("恢复默认设置…"), role: .destructive) { confirmReset = true }
            }
        }.formStyle(.grouped)
    }
    @ViewBuilder private var preview: some View {
        if let value = try? validatedDraft() {
            let work = ScheduleCalculator.snapshot(now: model.now, settings: value)
            let earnings = EarningsCalculator.calculate(now: model.now, settings: value, work: work)
            Text(String(format: L10n.text("有效工时 %.2f 小时 · 当月计划 %d 个工作日"), work.totalSeconds / 3600, ScheduleCalculator.plannedDays(now: model.now, settings: value)))
            if let daily = earnings.daily { Text(L10n.text("今日日薪 ") + (value.hideEarnings ? "¥••••" : Money.formatted(daily))).monospacedDigit() }
            if let reason = earnings.reason { Text(reason).foregroundStyle(.secondary) }
        } else { Text(L10n.text("填写有效金额和工作时间后显示预览。")).foregroundStyle(.secondary) }
    }
    private func dayName(_ day: Int) -> String { [1:L10n.text("周日"), 2:L10n.text("周一"), 3:L10n.text("周二"), 4:L10n.text("周三"), 5:L10n.text("周四"), 6:L10n.text("周五"), 7:L10n.text("周六")][day]! }
    private func timeField(_ title: String, value: Binding<String>, errorKey: String) -> some View {
        VStack(alignment: .leading) { TextField(title, text: value).monospacedDigit(); if let error = errors[errorKey] { Text(error).font(.caption).foregroundStyle(.red) } }
    }
    private func moneyField(_ title: String, value: Binding<String>, errorKey: String) -> some View {
        VStack(alignment: .leading) { TextField(title, text: value).monospacedDigit(); if let error = errors[errorKey] { Text(error).font(.caption).foregroundStyle(.red) } }
    }
    private func minute(_ text: String, field: String) throws -> Int {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { throw ValidationError(L10n.format("{0}：使用 HH:mm 格式", String(describing: field))) }
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts[0] < 24 && parts[1] < 60 else { throw ValidationError(L10n.format("{0}：小时 00–23，分钟 00–59", String(describing: field))) }
        return parts[0] * 60 + parts[1]
    }
    private func addDailyStart() {
        do {
            draft.dailyStartMinutes[ScheduleCalculator.key(flexibleDate, calendar: draft.calendar)] = try minute(flexibleTime, field: L10n.text("弹性上班"))
            errors["flexible"] = nil
        } catch { errors["flexible"] = error.localizedDescription }
    }
    private func validatedDraft() throws -> WorkSettings {
        var result = draft
        result.overtimeIntervalMinutes = try OvertimeCalculator.parseInterval(overtimeGap)
        result.cupVolumeML = try HydrationCalculator.parseCupVolume(cupVolume)
        result.startMinute = try minute(start, field: L10n.text("上班")); result.workDurationMinutes = try minute(duration, field: L10n.text("班次时长"))
        if result.lunchEnabled { result.lunchStart = try minute(lunchStart, field: L10n.text("午休开始")); result.lunchEnd = try minute(lunchEnd, field: L10n.text("午休结束")) }
        result.monthlySalary = try Money.parse(monthly)
        result.customDaily = try Money.parse(daily)
        guard let n = try Money.parse(days, maximum: 31), n >= 1 else { throw ValidationError(L10n.text("计薪天数须为 1–31")) }
        result.fixedDays = n
        return try result.validated()
    }
    private func save() {
        errors = [:]
        // Collect field errors before attempting any persistent or system mutation.
        for (key, text, title) in [("start", start, L10n.text("上班")), ("duration", duration, L10n.text("班次时长"))] + (draft.lunchEnabled ? [("lunchStart", lunchStart, L10n.text("午休开始")), ("lunchEnd", lunchEnd, L10n.text("午休结束"))] : []) {
            do { _ = try minute(text, field: title) } catch { errors[key] = error.localizedDescription }
        }
        for (key, text, max) in [("monthly", monthly, Decimal(10_000_000)), ("daily", daily, Decimal(10_000_000)), ("days", days, Decimal(31))] {
            do { _ = try Money.parse(text, maximum: max) } catch { errors[key] = error.localizedDescription }
        }
        do { _ = try OvertimeCalculator.parseInterval(overtimeGap) } catch { errors["overtimeGap"] = error.localizedDescription }
        do { _ = try HydrationCalculator.parseCupVolume(cupVolume) } catch { errors["cupVolume"] = error.localizedDescription }
        guard errors.isEmpty else { return }
        do { try model.save(validatedDraft(), launchAtLogin: launchAtLogin); close() } catch { errors["settings"] = error.localizedDescription }
    }
    private func reset() {
        draft = WorkSettings(); overtimeGap = "5"; flexibleTime = "09:00"; cupVolume = "500"; monthly = ""; daily = ""; days = "21.75"; start = "09:00"; duration = "09:00"; lunchStart = "12:00"; lunchEnd = "13:00"; launchAtLogin = false; errors = [:]
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var service: NotificationService
    var body: some View {
        Text(service.statusText)
        Button(service.status == .notDetermined ? L10n.text("开启通知") : L10n.text("打开系统通知设置")) { service.request() }
        Text(L10n.text("系统设置 → 通知 → 下班啦；专注模式与通知样式由系统控制。")).font(.caption).foregroundStyle(.secondary)
        if let issue = service.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
    }
}
private struct LoginStatusView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var service: LoginService
    var body: some View {
        Text(service.statusText).font(.caption).foregroundStyle(.secondary)
        if service.status == .requiresApproval { Button(L10n.text("打开登录项设置")) { service.openSettings() } }
        if let issue = service.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
    }
}

private struct DailyStartTimesView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @Binding var starts: [String: Int]
    @Binding var selectedDate: Date
    @Binding var selectedTime: String
    let calendar: Calendar
    @Binding var error: String?
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { dismiss() } label: {
                    Label(L10n.text("返回工作安排"), systemImage: "chevron.left")
                }
                Spacer()
                Text(L10n.format("{0} 条记录", String(starts.count))).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.top, 12)
            Form {
                Section(L10n.text("每天的开始时间")) {
                    DatePicker(L10n.text("日期（工作时区）"), selection: $selectedDate, displayedComponents: .date)
                    TextField(L10n.text("当天上班（HH:mm）"), text: $selectedTime).monospacedDigit()
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(L10n.text("添加 / 更新当天时间"), action: apply)
                    Text(L10n.text("修改后点击下方“保存”生效。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("已设置日期")) {
                    if starts.isEmpty {
                        Text(L10n.text("暂无单独设置的开始时间，所有日期使用默认时间。")).foregroundStyle(.secondary)
                    }
                    ForEach(starts.keys.sorted(), id: \.self) { key in
                        if let value = starts[key] {
                            HStack {
                                Text(key).monospacedDigit()
                                Text(ScheduleCalculator.timeLabel(value)).monospacedDigit()
                                Spacer()
                                Button(L10n.text("使用默认")) { starts.removeValue(forKey: key) }
                            }
                        }
                    }
                    Text(L10n.text("仅支持当天内班次。任务栏修改今日上班会同步到此处，并立即更新倒计时。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }.navigationTitle(L10n.text("每天的开始时间"))
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
}

private struct DateOverridesView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @Binding var overrides: [String: Bool]
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var workday = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { dismiss() } label: {
                    Label(L10n.text("返回工作安排"), systemImage: "chevron.left")
                }
                Spacer()
                Text(L10n.format("{0} 条记录", String(overrides.count))).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.top, 12)
            Form {
                Section(L10n.text("指定日期覆盖")) {
                    DatePicker(L10n.text("日期（工作时区）"), selection: $selectedDate, displayedComponents: .date)
                    HStack {
                        Picker(L10n.text("安排"), selection: $workday) {
                            Text(L10n.text("工作")).tag(true)
                            Text(L10n.text("休息")).tag(false)
                        }.pickerStyle(.segmented)
                        Button(L10n.text("添加 / 更新")) {
                            overrides[ScheduleCalculator.key(selectedDate, calendar: calendar)] = workday
                        }
                    }
                    Text(L10n.text("修改后点击下方“保存”生效。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("已设置日期")) {
                    if overrides.isEmpty {
                        Text(L10n.text("暂无日期覆盖")).foregroundStyle(.secondary)
                    }
                    ForEach(overrides.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).monospacedDigit()
                            Text(L10n.text(overrides[key] == true ? "工作" : "休息"))
                            Spacer()
                            Button(L10n.text("删除")) { overrides.removeValue(forKey: key) }
                        }
                    }
                }
            }.formStyle(.grouped)
        }.navigationTitle(L10n.text("指定日期覆盖"))
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
}

struct AssistantSettingsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    @State private var apiKey = ""
    @State private var status: String?
    var body: some View {
        NavigationStack { settingsForm }
    }
    private var settingsForm: some View {
        Form {
            Section(L10n.text("AI 助手")) {
                TextField(L10n.text("称谓"), text: $store.ownerName)
                TextField(L10n.text("天气城市"), text: $store.weatherCity)
                Text(L10n.text("默认上海，每次启动重新查询天气；问候仅每天首次启动展示。修改城市后下次启动生效。"))
                    .font(.caption).foregroundStyle(.secondary)
                Link(L10n.text("天气数据：Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                    .font(.caption)
                Picker(L10n.text("AI 模型"), selection: $store.modelID) {
                    if store.selectedModel == nil { Text(L10n.format("请选择模型（原模型：{0}）", store.modelID)).tag(store.modelID) }
                    ForEach(store.availableModels) { model in
                        Text(model.name + " · " + L10n.text(model.isFree ? "免费" : "低价") + (model.supportsImages ? " · " + L10n.text("视觉") : "")).tag(model.id)
                    }
                }
                if let model = store.selectedModel {
                    Text(model.isFree ? L10n.text("免费模型，额度与可用性由 OpenRouter 控制。") : L10n.format("基础价格 / 百万 token：输入 ${0} · 输出 ${1}", String(format: "%.3f", model.inputPrice * 1_000_000), String(format: "%.3f", model.outputPrice * 1_000_000)))
                        .font(.caption).foregroundStyle(.secondary)
                    if model.supportsImages {
                        Text(L10n.text("该模型支持图片输入；当前 App 聊天仅发送文字。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let expiration = model.expirationDate {
                        Text(L10n.format("预览版预计于 {0} 下线。", expiration))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.text("模型上下文上限"), value: "\(model.contextLength) token")
                    if let maximum = model.maximumOutputTokens {
                        LabeledContent(L10n.text("模型回复上限"), value: "\(maximum) token")
                    }
                    if model.effectiveContextLength < model.contextLength {
                        LabeledContent(L10n.text("当前供应商上下文上限"), value: "\(model.effectiveContextLength) token")
                    }
                    if model.hasTieredPricing == true {
                        Text(L10n.text("该模型按上下文长度分档计价，长上下文价格可能高于基础价格。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(L10n.text(store.refreshingModels ? "正在刷新…" : "刷新可用模型")) { Task { await store.refreshModels() } }.disabled(store.refreshingModels)
                if let issue = store.modelIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                Text(L10n.text("助手设置修改后立即保存。优先提供免费模型和低价开放权重模型；价格以 OpenRouter 实际结算为准。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("OpenRouter") {
                SecureField("API Key", text: $apiKey)
                Button(L10n.text("保存密钥")) {
                    do { try AssistantCredential.save(apiKey); apiKey = ""; status = "密钥已保存到本机应用数据。" }
                    catch { status = error.localizedDescription }
                }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let status { Text(L10n.text(status)).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L10n.text("用量")) {
                if let usage = store.latestUsage {
                    LabeledContent(L10n.text("最近一次输入 / 输出"), value: "\(usage.promptTokens) / \(usage.completionTokens) token")
                    if let model = store.messages.last(where: { $0.usage != nil })?.modelID {
                        LabeledContent(L10n.text("最近一次实际模型"), value: model)
                    }
                    LabeledContent(L10n.text("最近一次总量"), value: "\(usage.totalTokens) token")
                    LabeledContent(L10n.text("最近一次费用"), value: usage.cost.map { String(format: "$%.6f", $0) } ?? L10n.text("未返回"))
                } else { Text(L10n.text("尚未收到用量统计")).foregroundStyle(.secondary) }
                LabeledContent(L10n.text("本机已记录用量"), value: L10n.format("{0} token · {1} 次", String(store.recordedUsages.reduce(0) { $0 + $1.totalTokens }), String(store.recordedUsages.count)))
                LabeledContent(L10n.text("本机已记录费用"), value: String(format: "$%.6f", store.recordedUsages.compactMap(\.cost).reduce(0, +)))
                Text(L10n.text("仅统计本机聊天收到的实际用量；中断请求或旧消息可能缺失统计，不代表账户总用量。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("对话上下文")) {
                Picker(L10n.text("输入上下文预算"), selection: $store.inputTokenBudget) {
                    ForEach(AssistantContext.inputBudgetOptions, id: \.self) { Text("\($0) token").tag($0) }
                }
                Picker(L10n.text("单次回复上限"), selection: $store.outputTokenLimit) {
                    ForEach(AssistantContext.outputTokenOptions, id: \.self) { Text("\($0) token").tag($0) }
                }
                if let limits = store.effectiveTokenLimits {
                    Text(L10n.format("当前实际限额：输入 {0}，回复 {1} token。", String(limits.inputBudget), String(limits.outputTokens)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L10n.text("仅携带当天最近 6 轮完整对话。输入按 UTF-8 字节保守估算；实际限额会按模型和供应商容量自动缩减。增加上限可能增加费用。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("聊天历史")) {
                NavigationLink {
                    AssistantHistoryView(store: store)
                } label: {
                    HStack {
                        Text(L10n.text("查看聊天历史"))
                        Spacer()
                        Text(L10n.format("{0} 条记录", String(store.messages.count))).foregroundStyle(.secondary)
                    }
                }
            }
        }.formStyle(.grouped)
            .task { await store.refreshModels() }
    }
}

private struct AssistantHistoryView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { dismiss() } label: { Label(L10n.text("返回 AI 助手设置"), systemImage: "chevron.left") }
                Spacer()
                Text(L10n.format("{0} 条记录", String(store.messages.count))).foregroundStyle(.secondary)
                Button(L10n.text("导出 JSON"), action: export)
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if store.messages.isEmpty { Text(L10n.text("暂无聊天记录")).foregroundStyle(.secondary) }
                    ForEach(store.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L10n.text(message.role == .user ? "你" : "AI 助手")).font(.caption.bold())
                                Text(message.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                Text(message.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                if !message.complete { Text(L10n.text("未完成")).font(.caption).foregroundStyle(.secondary) }
                            }
                            MarkdownMessageView(source: message.contextContent.isEmpty ? L10n.text("未收到回复") : message.contextContent).textSelection(.enabled)
                            if let model = message.modelID { Text(model).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let usage = message.usage {
                                Text("\(usage.totalTokens) token" + (usage.cost.map { String(format: " · $%.6f", $0) } ?? " · " + L10n.text("费用未返回")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider().padding(.top, 8)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20).navigationTitle(L10n.text("聊天历史"))
            .environment(\.calendar, store.conversationCalendar).environment(\.timeZone, store.conversationCalendar.timeZone)
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "pet-chat-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(to: url); status = L10n.text("聊天历史已导出。") }
        catch { status = L10n.format("导出失败：{0}", error.localizedDescription) }
    }
}
