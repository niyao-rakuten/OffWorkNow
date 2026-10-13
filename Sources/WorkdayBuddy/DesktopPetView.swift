import SwiftUI
import AppKit
import WorkdayCore

struct DesktopPetView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    @State private var petIssue: String?
    var body: some View {
        VStack(spacing: 0) {
            PetControls(time: time, timeDescription: timeDescription,
                        cups: model.hydration.cups, cupVolume: model.settings.cupVolumeML,
                        totalML: model.hydration.totalML,
                        overtime: model.checkout.isOvertime, openSettings: openSettings,
                        drink: model.drinkWater, undoDrink: model.undoWater)
            PetAvatar(kind: model.settings.petKind, celebrating: model.checkout.isCheckedOut,
                      tired: model.checkout.isOvertime, animate: model.animationsActive,
                      custom: model.settings.customPet, drinkTrigger: model.drinkAnimationID,
                      animationTrigger: model.petAnimationID)
                .frame(width: 200, height: 200)
                .overlay(PetDragHandle(singleClick: model.cyclePetAnimation, doubleClick: cyclePet))
                .help(L10n.text("单击切换动作 · 双击切换形象 · 拖动移动位置"))
                .accessibilityAction(named: L10n.text("切换动作"), model.cyclePetAnimation)
                .accessibilityAction(named: L10n.text("切换伙伴"), cyclePet)
                .contextMenu {
                    Button(L10n.text("下一个动作"), action: model.cyclePetAnimation)
                    Button(L10n.text("下一个伙伴"), action: cyclePet)
                    Button(L10n.text("设置"), action: openSettings)
                    Button(L10n.text("退出下班啦")) { NSApp.terminate(nil) }
                }
            PetCheckoutButton(visible: model.work.state == .after && model.checkout.canCheckout,
                              checkout: model.checkoutNow)
        }
        .padding(.top, 4).frame(width: 240, height: 290, alignment: .top)
        .alert(model.waterIssue != nil ? L10n.text("喝水记录未保存") : L10n.text("无法切换伙伴"), isPresented: Binding(get: { model.waterIssue != nil || petIssue != nil }, set: { if !$0 { model.waterIssue = nil; petIssue = nil } })) {
            Button(L10n.text("好")) { model.waterIssue = nil; petIssue = nil }
        } message: { Text(model.waterIssue ?? petIssue ?? "") }
    }
    private func cyclePet() { do { try model.cyclePet() } catch { petIssue = error.localizedDescription } }
    private var time: String {
        if model.checkout.isCheckedOut, let date = model.checkoutStore.record?.checkedOutAt {
            let components = model.settings.calendar.dateComponents([.hour, .minute], from: date)
            return "✓ " + ScheduleCalculator.timeLabel((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        if model.work.state == .rest { return "— : — : —" }
        if model.checkout.isOvertime {
            return "+" + ScheduleCalculator.countdown(model.checkout.overtimeSeconds, secondsIncluded: true)
        }
        return ScheduleCalculator.countdown(max(0, model.work.end.timeIntervalSince(model.now)), secondsIncluded: true)
    }
    private var timeDescription: String {
        if model.checkout.isCheckedOut { return L10n.text("今天已打卡下班") }
        if model.work.state == .rest { return L10n.text("今天休息") }
        if model.checkout.isOvertime { return L10n.text("已加班 ") + model.checkout.duration }
        return L10n.text("下班倒计时 ") + time
    }
}

struct WelcomeView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var notifications: NotificationService
    let finish: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            PetAvatar(kind: .cat).frame(width: 130, height: 130)
            Text(L10n.text("下班啦")).font(.largeTitle.bold())
            Text(L10n.text("陪你认真工作，也提醒你准时收工。")).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("菜单栏查看工资、安排和提醒"), systemImage: "menubar.rectangle")
                Label(L10n.text("桌面伙伴陪你倒计时，可拖动和切换"), systemImage: "pawprint")
                Label(L10n.text("点击“打卡下班”打卡，结束当天提醒"), systemImage: "checkmark.circle")
            }.font(.subheadline)
            Text(L10n.text("月薪默认留空；打卡只保存在本机，不向公司提交。通知由你主动授权。")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button(L10n.text("开启通知")) { notifications.request() }
                Button(L10n.text("开始使用"), action: finish).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460, height: 500)
    }
}

