import AppKit
import SwiftUI
import Combine
import WorkdayCore

@main enum WorkdayBuddyMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppModel: ObservableObject {
    let bot = AIBot()
    let store = SettingsStore()
    let notifications = NotificationService()
    let speech = SpeechService()
    let login = LoginService()
    let checkoutStore = CheckoutStore()
    let hydrationStore = HydrationStore()
    let reports = DailyReportStore()
    let assistant = AssistantStore()
    @Published var chatVisible = false {
        didSet { assistant.setPanelVisible(chatVisible) }
    }
    @Published var selectedSettingsTab = "schedule"
    @Published var waterIssue: String?
    @Published var animationsActive = true
    @Published private(set) var drinkAnimationID = 0
    @Published private(set) var petAnimationID = 0
    let reminders: ReminderCoordinator
    @Published private(set) var now: Date
    @Published private(set) var work: WorkSnapshot
    @Published private(set) var earnings: EarningsSnapshot
    private let clock: any Clock
    var settings: WorkSettings { store.settings }
    var botContext: AIBotContext { AIBotContext(now: now, settings: settings, checkout: checkoutStore.record, hydration: hydration) }
    init(clock: any Clock = SystemClock()) {
        self.clock = clock; now = clock.now
        let initial = bot.inspect(AIBotContext(now: clock.now, settings: store.settings))
        work = initial.work
        earnings = initial.earnings
        reminders = ReminderCoordinator(notifications: notifications, speech: speech, clock: clock)
        reminders.onMessage = { [weak self] localized in
            self?.assistant.receive(localized)
        }
        Task { [weak self] in await self?.assistant.sendStartupGreeting() }
    }
    func refresh(forceReport: Bool = false) {
        now = clock.now
        let state = bot.inspect(botContext)
        work = state.work; earnings = state.earnings; reminders.expirePause()
        reports.capture(now: now, settings: settings, checkout: checkoutStore.record, hydration: hydration, force: forceReport)
    }
    func save(_ settings: WorkSettings, launchAtLogin: Bool) throws {
        _ = try settings.validated()
        if settings.petKind == .custom, let config = settings.customPet { try CustomPetLibrary.validateFile(config) }
        let oldAsset = self.settings.customPet?.assetID
        if launchAtLogin != login.enabled { try login.setEnabled(launchAtLogin) }
        try store.save(settings)
        if let oldAsset { CustomPetLibrary.discard([oldAsset], keeping: settings.customPet?.assetID) }
        reminders.configure(settings, checkout: checkoutStore.record); refresh(forceReport: true)
    }
    var todayStartMinute: Int { settings.startMinute(on: now) }
    func setTodayStart(_ minute: Int?) throws {
        refresh()
        var value = settings
        let key = ScheduleCalculator.key(now, calendar: settings.calendar)
        value.dailyStartMinutes[key] = minute
        try save(value, launchAtLogin: login.enabled)
    }
    var hydration: HydrationSummary { hydrationStore.log?.summary(now: now, settings: settings) ?? HydrationSummary(cups: 0, totalML: 0) }
    func drinkWater() {
        refresh()
        do { try hydrationStore.drink(now: now, settings: settings); drinkAnimationID += 1; waterIssue = nil; refresh(forceReport: true) }
        catch { waterIssue = error.localizedDescription }
    }
    func cyclePet() throws {
        var value = settings
        let hasCustom = value.customPet.map { (try? CustomPetLibrary.validateFile($0)) != nil } ?? false
        value.petKind = value.petKind.next(customAvailable: hasCustom)
        try store.save(value)
        refresh()
    }
    func cyclePetAnimation() { petAnimationID &+= 1 }
    func undoWater() { refresh(); hydrationStore.undo(now: now, settings: settings); refresh(forceReport: true) }
    var checkout: CheckoutSnapshot { bot.inspect(botContext).checkout }
    func checkoutNow() {
        refresh()
        let actions = bot.handle(.checkout, in: botContext)
        guard !actions.isEmpty else { return }
        for action in actions {
            switch action {
            case .recordCheckout(let record): checkoutStore.checkout(now: record.checkedOutAt, settings: settings)
            case .showMessagePanel: chatVisible = true
            case .postMessage(let message): assistant.receive(message.localizedContents)
            case .deliverReminder: break // ReminderCoordinator owns notification delivery.
            }
        }
        reminders.configure(settings, checkout: checkoutStore.record); refresh(forceReport: true)
    }
    func undoCheckout() { checkoutStore.undo(); reminders.configure(settings); refresh(forceReport: true) }
    #if DEBUG
    func debugClearData(on date: Date) throws {
        guard !assistant.isStreaming else { throw ValidationError("请先停止 AI 回复，再清除数据。") }
        let key = ScheduleCalculator.key(date, calendar: settings.calendar)
        try reports.debugClear(dateKey: key, timeZoneID: settings.timeZoneID)
        try assistant.debugClear(dateKey: key, calendar: settings.calendar)
        checkoutStore.debugClear(dateKey: key, timeZoneID: settings.timeZoneID)
        hydrationStore.debugClear(dateKey: key, timeZoneID: settings.timeZoneID)
        reminders.debugClear(dateKey: key, timeZoneID: settings.timeZoneID)
        reminders.configure(settings, checkout: checkoutStore.record)
        waterIssue = nil
        refresh()
    }
    #endif
    var statusTitle: String { checkout.isCheckedOut ? L10n.text("已打卡下班") : checkout.isOvertime ? L10n.text("加班中") : work.state.title }
    func amount(_ value: Decimal?) -> String { settings.hideEarnings ? "¥••••" : value.map(Money.formatted) ?? "—" }
    var menuTitle: String {
        if settings.menuMode == .countdown {
            if checkout.isCheckedOut { return L10n.text("下班啦 ✓") }
            if checkout.isOvertime { return L10n.text("加班 ") + checkout.duration }
        }
        return DisplayFormatter.menu(settings: settings, work: work, earnings: earnings)
    }
    var dateTitle: String {
        let formatter = DateFormatter(); formatter.calendar = settings.calendar; formatter.timeZone = settings.calendar.timeZone
        formatter.locale = L10n.locale; formatter.dateFormat = L10n.text("M月d日 EEEE"); return formatter.string(from: now)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var reportsWindow: NSWindow?
    private var petWindow: NSPanel?
    private var settingsSubscription: AnyCancellable?
    private var displayTimer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    private var chatSubscription: AnyCancellable?
    private var chatWindow: NSPanel?
    private var chatFadeGeneration = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        languageSubscription = AppLanguageStore.shared.$selection.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.settingsWindow?.title = L10n.text("下班啦 · 设置")
                self.reportsWindow?.title = L10n.text("下班啦 · 收工日记")
                self.model.notifications.refresh()
                self.model.login.refresh()
                self.model.refresh()
                self.updateTitle()
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: L10n.text("下班啦"))
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePanel)
        popover = NSPopover(); popover.behavior = .transient; popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 660)
        popover.contentViewController = NSHostingController(rootView: AppLanguageView { MenuPanelView(model: self.model, openReports: { [weak self] in self?.showReports() }, openSettings: { [weak self] in self?.showSettings() }) })
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle(); self?.positionChatWindow() }
        }
        settingsSubscription = model.store.$settings.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncPetWindow(); self?.refreshDisplay() }
        }
        model.reminders.configure(model.settings, checkout: model.checkoutStore.record, startup: true)
        syncPetWindow()
        chatSubscription = model.$chatVisible.dropFirst().sink { [weak self] visible in
            DispatchQueue.main.async {
                guard let self, self.model.chatVisible == visible else { return }
                self.setChatWindowVisible(visible)
            }
        }
        model.refresh(forceReport: true)
        showReports()
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { [weak self] in self?.displayTimer?.invalidate(); self?.model.animationsActive = false; self?.model.reminders.suspend() }
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in self?.recover() }
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.model.animationsActive = false; self?.model.speech.stop() }
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.recover() }
        watch(.default, NSApplication.didBecomeActiveNotification) { [weak self] in self?.model.notifications.refresh(); self?.model.login.refresh(); self?.recover() }
        watch(.default, Notification.Name("NSSystemClockDidChangeNotification")) { [weak self] in self?.recover() }
        watch(.default, NSNotification.Name.NSSystemTimeZoneDidChange) { [weak self] in self?.recover() }
        watch(.default, .NSCalendarDayChanged) { [weak self] in self?.recover() }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.model.animationsActive = false; self?.model.speech.stop() }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.model.animationsActive = true; self?.model.speech.refreshSession() }
        refreshDisplay()
    }
    private func watch(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor in action() } }
        observers.append((center, token))
    }
    private func recover() { model.animationsActive = true; model.refresh(); model.reminders.recover(); refreshDisplay() }
    private func updateTitle() { statusItem.button?.title = model.menuTitle; statusItem.button?.setAccessibilityLabel(L10n.text("下班啦，") + (model.menuTitle.isEmpty ? model.work.state.title : model.menuTitle)) }
    private func refreshDisplay() {
        displayTimer?.invalidate(); model.refresh(); updateTitle()
        let c = model.settings.calendar
        let nextMinute = c.nextDate(after: model.now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)!
        let boundaries = model.work.intervals.flatMap { [$0.start, $0.end] } + [model.work.start, model.work.end, c.date(byAdding: .day, value: 1, to: c.startOfDay(for: model.now))!]
        let nearest = boundaries.filter { $0 > model.now }.min() ?? nextMinute
        let delay = (popover.isShown || petWindow?.isVisible == true) ? 1.0 : max(0.05, min(nextMinute.timeIntervalSince(model.now), nearest.timeIntervalSince(model.now)))
        displayTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in Task { @MainActor in self?.refreshDisplay() } }
        RunLoop.main.add(displayTimer!, forMode: .common)
    }
    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else if let button = statusItem.button {
            model.notifications.refresh(); model.speech.refreshSession(); model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        refreshDisplay()
    }
    func popoverDidClose(_ notification: Notification) { refreshDisplay() }
    func showAssistantSettings() {
        model.selectedSettingsTab = "assistant"
        showSettings()
    }
    func showSettings() {
        popover.performClose(nil)
        if let settingsWindow { NSApp.activate(ignoringOtherApps: true); settingsWindow.makeKeyAndOrderFront(nil); return }
        model.login.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("下班啦 · 设置"); window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 590, height: 540)
        window.contentViewController = NSHostingController(rootView: AppLanguageView { SettingsView(model: self.model, close: { [weak self] in self?.settingsWindow?.close() }) })
        settingsWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    private func syncPetWindow() {
        guard model.settings.petEnabled || model.chatVisible || chatWindow?.isVisible == true else { petWindow?.orderOut(nil); return }
        if petWindow == nil {
            let panel = DesktopPetPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 330), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: AppLanguageView { DesktopPetView(model: self.model, openReports: { [weak self] in self?.showReports() }, openSettings: { [weak self] in self?.showSettings() }) })
            if !panel.setFrameUsingName("DesktopPet") {
                let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
                panel.setFrameOrigin(NSPoint(x: area.maxX - 260, y: area.minY + 24))
            }
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
                let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
                panel.setFrameOrigin(NSPoint(x: area.maxX - 260, y: area.minY + 24))
            }
            let collapsed = PetPanelLayout(position: model.settings.chatPanelPosition, expanded: false)
            let expanded = PetPanelLayout(position: model.settings.chatPanelPosition, expanded: true)
            if panel.frame.size == expanded.size {
                panel.setFrame(collapsed.windowFrame(from: panel.frame, previous: expanded), display: false)
            }
            panel.setContentSize(PetPanelLayout.petSize)
            panel.setFrame(collapsed.windowFrame(from: panel.frame, previous: collapsed, visibleFrame: panel.screen?.visibleFrame), display: false)
            panel.setFrameAutosaveName("DesktopPet"); panel.delegate = self; petWindow = panel
        }
        petWindow?.level = model.settings.petAlwaysOnTop ? .floating : .normal
        positionChatWindow()
        petWindow?.orderFrontRegardless()
    }
    private func positionChatWindow() {
        guard let pet = petWindow, let chat = chatWindow else { return }
        let frame = PetPanelLayout.chatWindowFrame(relativeTo: pet.frame, position: model.settings.chatPanelPosition,
                                                   visibleFrame: pet.screen?.visibleFrame)
        chat.level = pet.level
        if chat.frame != frame { chat.setFrame(frame, display: true, animate: false) }
    }
    private func setChatWindowVisible(_ visible: Bool) {
        chatFadeGeneration += 1
        let generation = chatFadeGeneration
        if visible {
            popover.performClose(nil)
            syncPetWindow()
            guard let pet = petWindow else { return }
            if chatWindow == nil {
                let panel = DesktopPetPanel(contentRect: CGRect(origin: .zero, size: PetPanelLayout.chatSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentViewController = NSHostingController(rootView: AppLanguageView {
                    FloatingAssistantChatView(model: self.model, openSettings: { [weak self] in self?.showAssistantSettings() })
                })
                chatWindow = panel
            }
            guard let chat = chatWindow else { return }
            positionChatWindow()
            if !chat.isVisible { chat.alphaValue = 0 }
            chat.ignoresMouseEvents = false
            if chat.parent !== pet { pet.addChildWindow(chat, ordered: .above) }
            chat.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
                chat.animator().alphaValue = 1
            }
        } else if let chat = chatWindow {
            chat.ignoresMouseEvents = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
                chat.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak chat] in
                Task { @MainActor in
                    guard let self, let chat, self.chatFadeGeneration == generation, !self.model.chatVisible else { return }
                    chat.orderOut(nil); chat.parent?.removeChildWindow(chat)
                    self.syncPetWindow()
                }
            })
        }
    }
    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === petWindow { positionChatWindow() }
    }
    func showReports() {
        popover.performClose(nil)
        model.refresh(forceReport: true)
        if let reportsWindow { NSApp.activate(ignoringOtherApps: true); reportsWindow.makeKeyAndOrderFront(nil); return }
        let height = min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("下班啦 · 收工日记"); window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 540, height: 860)
        window.contentViewController = NSHostingController(rootView: AppLanguageView { MacReportsView(model: self.model, openSettings: { [weak self] in self?.showSettings() }) })
        reportsWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { settingsWindow = nil }
        if notification.object as? NSWindow === reportsWindow { reportsWindow = nil }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        chatFadeGeneration += 1; chatWindow?.orderOut(nil)
        model.refresh(forceReport: true)
        displayTimer?.invalidate(); petWindow?.saveFrame(usingName: "DesktopPet"); model.reminders.stop()
        for (center, token) in observers { center.removeObserver(token) }
    }
}

private final class DesktopPetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct MacReportsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("照顾好自己，再继续闪闪发光。")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("通知与偏好设置"), action: openSettings)
            }.padding(12)
            DailyReportsView(store: model.reports, settings: model.settings, now: model.now)
        }
    }
}

private struct FloatingAssistantChatView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    var body: some View {
        AssistantChatView(store: model.assistant, openSettings: openSettings,
                          close: { model.chatVisible = false }, isPresented: model.chatVisible)
            .frame(width: PetPanelLayout.chatSize.width, height: PetPanelLayout.chatSize.height)
    }
}
