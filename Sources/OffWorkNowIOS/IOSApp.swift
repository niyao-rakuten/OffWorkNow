import SwiftUI
import UserNotifications
import WorkdayCore

@main struct OffWorkNowIOSApp: App {
    @StateObject private var model = MobileModel()
    @ObservedObject private var language = AppLanguageStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppLanguageView { TabView {
                DailyReportsView(store: model.reports, settings: model.settings, now: model.now)
                    .tabItem { Label(L10n.text("日记"), systemImage: "calendar") }
                MobileDashboard(model: model).tabItem { Label(L10n.text("今日"), systemImage: "sun.max") }
            }
            }
                .onChange(of: language.selection) { _ in Task { await model.scheduleOffwork() } }
                .onAppear { model.activate() }
                .onChange(of: scenePhase) { phase in if phase == .active { model.activate() } else { model.deactivate() } }
        }
    }
}

@MainActor final class MobileModel: ObservableObject {
    private let bot = AIBot()
    private var botContext: AIBotContext { AIBotContext(now: now, settings: settings, checkout: checkoutRecord, hydration: hydration) }
    @Published private(set) var settings: WorkSettings
    @Published private(set) var now = Date()
    @Published private(set) var checkoutRecord: CheckoutRecord?
    @Published private(set) var hydrationLog: HydrationLog?
    @Published private(set) var drinkAnimationID = 0
    @Published var notificationAllowed = false
    @Published var error: String?
    let reports = DailyReportStore()
    private var timer: Timer?
    private let notificationDelegate = MobileNotificationDelegate()
    private let defaults = UserDefaults.standard
    init() {
        settings = defaults.data(forKey: "settings").flatMap { try? SettingsCodec.decode($0) } ?? WorkSettings()
        checkoutRecord = defaults.data(forKey: "latestCheckout").flatMap { try? JSONDecoder().decode(CheckoutRecord.self, from: $0) }
        if let data = defaults.data(forKey: "waterCups"), let decoded = try? JSONDecoder().decode(HydrationLog.self, from: data) { hydrationLog = try? decoded.validated() }
        defaults.set(try? JSONEncoder().encode(settings), forKey: "settings")
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    var hydration: HydrationSummary { hydrationLog?.summary(now: now, settings: settings) ?? HydrationSummary(cups: 0, totalML: 0) }
    func drinkWater() {
        now = Date(); var value = hydrationLog ?? HydrationLog(now: now, settings: settings)
        do { try value.add(now: now, settings: settings); hydrationLog = value; defaults.set(try JSONEncoder().encode(value), forKey: "waterCups"); drinkAnimationID += 1; captureReport(force: true) }
        catch { self.error = error.localizedDescription }
    }
    func undoWater() { now = Date(); hydrationLog?.undoLast(now: now, settings: settings); defaults.set(try? JSONEncoder().encode(hydrationLog), forKey: "waterCups"); captureReport(force: true) }
    var work: WorkSnapshot { bot.inspect(botContext).work }
    var checkout: CheckoutSnapshot { bot.inspect(botContext).checkout }
    var earnings: EarningsSnapshot { bot.inspect(botContext).earnings }
    var overtimeNotice: String? { bot.inspect(botContext).overtimeNotice }
    func activate() {
        now = Date(); captureReport(force: true); timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date(); self?.captureReport() } }
        Task { await scheduleOffwork() }
    }
    func deactivate() { now = Date(); captureReport(force: true); timer?.invalidate(); timer = nil }
    func checkoutNow() {
        now = Date()
        let actions = bot.handle(.checkout, in: botContext)
        guard let record = actions.compactMap({ action -> CheckoutRecord? in
            if case .recordCheckout(let record) = action { return record }
            return nil
        }).first else { return }
        checkoutRecord = record
        defaults.set(try? JSONEncoder().encode(checkoutRecord), forKey: "latestCheckout")
        captureReport(force: true)
        Task { await scheduleOffwork() }
    }
    func undoCheckout() { now = Date(); checkoutRecord = nil; defaults.removeObject(forKey: "latestCheckout"); captureReport(force: true); Task { await scheduleOffwork() } }
    func save(_ draft: WorkSettings) throws {
        let valid = try draft.validated()
        if valid.petKind == .custom, let config = valid.customPet { try CustomPetLibrary.validateFile(config) }
        let oldAsset = settings.customPet?.assetID
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: "settings"); settings = valid; now = Date()
        if let oldAsset { CustomPetLibrary.discard([oldAsset], keeping: valid.customPet?.assetID) }
        captureReport(force: true)
        Task { await scheduleOffwork() }
    }
    func captureReport(force: Bool = false) {
        reports.capture(now: now, settings: settings, checkout: checkoutRecord, hydration: hydration, force: force)
    }
    func enableNotifications() {
        Task {
            do { notificationAllowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); await scheduleOffwork() }
            catch { self.error = error.localizedDescription }
        }
    }
    private var notificationTask: Task<Void, Never>?
    func scheduleOffwork() async {
        let previous = notificationTask
        let task = Task { [weak self] in
            await previous?.value
            if let self { await self.performOffworkPlanning() }
        }
        notificationTask = task
        await task.value
    }
    private func performOffworkPlanning() async {
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        notificationAllowed = authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("offwork.") }.map(\.identifier))
        guard notificationAllowed, settings.offworkEnabled else { return }
        let c = settings.calendar
        let context = AIBotContext(now: Date(), settings: settings, checkout: checkoutRecord)
        for event in bot.upcomingOffwork(in: context) {
            let text = bot.reminderMessage(event, settings: settings).text()
            let content = UNMutableNotificationContent(); content.title = text.title; content.body = text.body
            if settings.notificationSound { content.sound = .default }
            var components = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date); components.calendar = c; components.timeZone = c.timeZone
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do { try await center.add(request) } catch { self.error = error.localizedDescription }
            }
    }
}

struct MobileDashboard: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: MobileModel
    @State private var showSettings = false
    @State private var confirmUndo = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(model.checkout.isCheckedOut ? L10n.text("今天收工啦") : model.checkout.isOvertime ? L10n.text("加班中") : model.work.state.title).font(.headline).foregroundStyle(.secondary)
                    PetAvatar(kind: model.settings.petKind, celebrating: model.checkout.isCheckedOut, tired: model.checkout.isOvertime, animate: scenePhase == .active, custom: model.settings.customPet, drinkTrigger: model.drinkAnimationID).frame(width: 200, height: 200)
                    Text(title).font(.title2.weight(.semibold))
                    Text(time).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    ProgressView(value: model.work.progress).accessibilityLabel(L10n.text("计划工作进度"))
                    if let notice = model.overtimeNotice {
                        Text(notice).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    if let earned = model.earnings.earned { Text(L10n.text("今日估算 ") + (model.settings.hideEarnings ? "¥••••" : Money.formatted(earned))).font(.title3).monospacedDigit() }
                    else { Text(model.earnings.reason ?? L10n.text("设置月薪后查看收入")).foregroundStyle(.secondary) }
                    Button(model.checkout.isCheckedOut ? L10n.text("已下班 ✓") : L10n.text("打卡下班")) { model.checkoutNow() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.checkout.canCheckout)
                    if model.checkout.isCheckedOut { Button(L10n.text("撤销今日打卡")) { confirmUndo = true } }
                    VStack(spacing: 8) {
                        Label(model.hydration.title, systemImage: "drop.fill").monospacedDigit()
                        Button(L10n.format("喝一杯水 +{0} ml", String(describing: model.settings.cupVolumeML))) { model.drinkWater() }.buttonStyle(.bordered)
                        if model.hydration.cups > 0 { Button(L10n.text("撤销上一杯")) { model.undoWater() }.font(.caption) }
                    }
                    if !model.notificationAllowed { Button(L10n.text("开启下班通知")) { model.enableNotifications() }; Text(L10n.text("若已拒绝，请在系统设置 → 通知 → 下班啦中开启。")).font(.caption).foregroundStyle(.secondary) }
                    Text(L10n.text("打卡仅保存在本机；工资按计划估算，不计加班。iOS 精灵在应用内展示。")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(28)
            }.navigationTitle(L10n.text("下班啦"))
            .toolbar { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel(L10n.text("设置")) }
            .sheet(isPresented: $showSettings) { MobileSettings(model: model) }
            .alert(L10n.text("撤销今日打卡？"), isPresented: $confirmUndo) { Button(L10n.text("取消"), role: .cancel) {}; Button(L10n.text("撤销")) { model.undoCheckout() } }
        }
    }
    private var title: String { model.checkout.isCheckedOut ? L10n.text("下班啦，明天见！") : model.checkout.isOvertime ? L10n.text("已经加班") : model.work.state == .rest ? L10n.text("今天休息") : model.work.state == .before ? L10n.text("今日上班时间") : L10n.text("距离下班") }
    private var time: String { model.checkout.isCheckedOut ? "✓" : model.checkout.isOvertime ? model.checkout.duration : model.work.state == .rest ? L10n.text("好好休息") : model.work.state == .before ? ScheduleCalculator.timeLabel(model.settings.startMinute(on: model.now)) : ScheduleCalculator.countdown(model.work.remaining, secondsIncluded: true) }
}

private final class MobileNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}
