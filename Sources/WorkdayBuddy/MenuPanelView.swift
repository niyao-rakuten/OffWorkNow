import SwiftUI
import AppKit
import WorkdayCore

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    let openReports: () -> Void
    let openSettings: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("下班啦", systemImage: "sun.max.fill").font(.headline)
                    Spacer()
                    Text(model.statusTitle).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5).background(.quaternary, in: Capsule())
                }
                Text(model.dateTitle).font(.subheadline).foregroundStyle(.secondary)
                countdown
                CheckoutControls(model: model)
                TodayStartEditor(model: model)
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.work.progress).accessibilityLabel("今日工作进度")
                    Text("已完成 \(Int(model.work.progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                earnings
                VStack(alignment: .leading, spacing: 7) {
                    Label(model.hydration.title, systemImage: "drop.fill").font(.subheadline).monospacedDigit()
                    HStack {
                        Button("喝一杯水 +\(model.settings.cupVolumeML) ml") { model.drinkWater() }
                        if model.hydration.cups > 0 { Button("撤销上一杯") { model.undoWater() }.buttonStyle(.link) }
                    }.controlSize(.small)
                    if let issue = model.waterIssue { Text(issue).font(.caption).foregroundStyle(.red) }
                }
                Text("按设置的工作时间估算，不代表实际到账或考勤结算").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(ScheduleCalculator.timeLabel(model.todayStartMinute))–\(ScheduleCalculator.timeLabel(model.settings.endMinute(on: model.now))) · \(model.settings.timeZoneID)", systemImage: "clock")
                    if model.settings.lunchEnabled { Text("午休 \(ScheduleCalculator.timeLabel(model.settings.lunchStart))–\(ScheduleCalculator.timeLabel(model.settings.lunchEnd)) · 不计薪") }
                    Text(model.settings.payMode.title + (model.settings.payMode == .fixedDays ? " · \(Money.input(model.settings.fixedDays)) 天/月" : ""))
                }.font(.caption).foregroundStyle(.secondary)
                Divider()
                ReminderPanel(model: model)
                if let message = model.store.recoveryMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                Divider()
                HStack {
                    Button(action: openReports) { Label("每日报表", systemImage: "calendar") }
                    Button(action: openSettings) { Label("设置", systemImage: "gearshape") }.keyboardShortcut(",", modifiers: .command)
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
                }.buttonStyle(.borderless)
            }.padding(22)
        }.frame(width: 360).frame(maxHeight: 740)
    }
    @ViewBuilder private var countdown: some View {
        VStack(alignment: .leading, spacing: 5) {
            if model.checkout.isCheckedOut {
                Text("下班啦！").font(.title.weight(.semibold))
                Text("已记录今日下班 · 加班 " + model.checkout.duration).font(.caption).foregroundStyle(.secondary)
            } else if model.checkout.isOvertime {
                Text("已经加班").font(.subheadline).foregroundStyle(.orange)
                Text(ScheduleCalculator.countdown(model.checkout.overtimeSeconds, secondsIncluded: true)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("点击“打卡下班”，结束今天的工作。").font(.caption).foregroundStyle(.secondary)
            } else { switch model.work.state {
            case .working, .lunch:
                Text("距离下班").font(.subheadline).foregroundStyle(.secondary)
                Text(ScheduleCalculator.countdown(model.work.remaining, secondsIncluded: true)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit().accessibilityLabel("距离下班 " + ScheduleCalculator.countdown(model.work.remaining, secondsIncluded: true))
            case .before: Text("今日 \(ScheduleCalculator.timeLabel(model.todayStartMinute)) 上班").font(.title2.weight(.semibold))
            case .rest: Text("今天休息").font(.title.weight(.semibold)); Text("给自己留一点自在的时间。").foregroundStyle(.secondary)
            case .after: Text("到下班时间啦").font(.title.weight(.semibold)); Text("收好今天，轻松下班。").foregroundStyle(.secondary)
            } }
        }
    }
    @ViewBuilder private var earnings: some View {
        if model.earnings.earned != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天已赚").font(.subheadline).foregroundStyle(.secondary)
                Text(model.amount(model.earnings.earned)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().textSelection(.enabled)
                Text("今日预计 " + model.amount(model.earnings.daily)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        } else {
            Button(model.earnings.reason ?? "设置工资") { openSettings() }.buttonStyle(.link)
        }
    }
}

private struct ReminderPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var reminders: ReminderCoordinator
    @ObservedObject private var notifications: NotificationService
    init(model: AppModel) { self.model = model; reminders = model.reminders; notifications = model.notifications }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(reminderTitle, systemImage: "bell").font(.subheadline)
            Text(notifications.statusText).font(.caption).foregroundStyle(.secondary)
            if !notifications.authorized {
                Text("开启通知后可收到整点与下班提醒。").font(.caption).foregroundStyle(.secondary)
                Button(notifications.status == .notDetermined ? "开启通知" : "打开系统通知设置") { notifications.request() }
                if notifications.status == .denied { Text("系统设置 → 通知 → 下班啦").font(.caption).foregroundStyle(.secondary) }
            }
            if reminders.pause != nil {
                Button("恢复提醒") { reminders.resume() }
            } else {
                HStack {
                    Button("暂停 1 小时") { reminders.pauseForHour() }.disabled(!model.settings.hourlyEnabled)
                    Button("暂停至下班") { reminders.pauseUntilOffwork() }.disabled(!model.settings.hourlyEnabled || model.work.state == .rest || model.work.state == .after)
                }.controlSize(.small)
            }
            if let issue = notifications.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
        }
    }
    private var reminderTitle: String {
        if !model.settings.hourlyEnabled { return "整点提醒已关闭" }
        if let pause = reminders.pause {
            let f = DateFormatter(); f.timeZone = model.settings.calendar.timeZone; f.dateFormat = "HH:mm"
            return "整点提醒暂停至 " + f.string(from: pause.until)
        }
        return "整点提醒已开启"
    }
}

private struct CheckoutControls: View {
    @ObservedObject var model: AppModel
    @State private var confirmUndo = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.checkout.isCheckedOut {
                Button("撤销今日打卡") { confirmUndo = true }.buttonStyle(.link)
            } else {
                Button("打卡下班") { model.checkoutNow() }.buttonStyle(.borderedProminent).disabled(!model.checkout.canCheckout)
            }
            Text("本地打卡，停止当天提醒；工资仍按原计划估算，不计加班。").font(.caption).foregroundStyle(.secondary)
        }.alert("撤销今天的下班打卡？", isPresented: $confirmUndo) {
            Button("取消", role: .cancel) {}
            Button("撤销") { model.undoCheckout() }
        } message: { Text("将恢复后续提醒；已经错过的提醒不会补发。") }
    }
}

private struct TodayStartEditor: View {
    @ObservedObject var model: AppModel
    @State private var selected = Date()
    @State private var error: String?
    var body: some View {
        DisclosureGroup("今日上班 \(ScheduleCalculator.timeLabel(model.todayStartMinute)) · 弹性调整") {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("今天几点上班", selection: $selected, displayedComponents: .hourAndMinute).environment(\.timeZone, model.settings.calendar.timeZone).environment(\.calendar, model.settings.calendar)
                HStack {
                    Button("应用到今天") {
                        let c = model.settings.calendar
                        do { try model.setTodayStart(c.component(.hour, from: selected) * 60 + c.component(.minute, from: selected)); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                    Button("使用默认 \(ScheduleCalculator.timeLabel(model.settings.startMinute))") {
                        do { try model.setTodayStart(nil); error = nil } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.link)
                }.controlSize(.small)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Text("同步保存到弹性上班；下班倒计时立即更新，午休仍不计薪。").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }.onAppear { selected = model.work.start }
    }
}
