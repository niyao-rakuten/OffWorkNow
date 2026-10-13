import AppKit
import Combine
import UserNotifications
import AVFoundation
import ServiceManagement
import WorkdayCore

@MainActor final class SettingsStore: ObservableObject {
    @Published private(set) var settings: WorkSettings
    @Published var recoveryMessage: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "settings") {
            do { settings = try SettingsCodec.decode(data) }
            catch { settings = WorkSettings(); recoveryMessage = "本地配置损坏或版本不支持，已恢复默认设置。"; defaults.removeObject(forKey: "settings") }
        } else { settings = WorkSettings() }
        // Persist the initial timezone immediately; travel must not silently change it.
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "settings") }
    }
    func save(_ value: WorkSettings) throws {
        let valid = try value.validated()
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: "settings"); settings = valid; recoveryMessage = nil
    }
}

@MainActor final class CheckoutStore: ObservableObject {
    @Published private(set) var record: CheckoutRecord?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        record = defaults.data(forKey: "latestCheckout").flatMap { try? JSONDecoder().decode(CheckoutRecord.self, from: $0) }
    }
    func checkout(now: Date, settings: WorkSettings) {
        guard record?.applies(now: now, settings: settings) != true else { return }
        record = CheckoutRecord(now: now, settings: settings)
        defaults.set(try? JSONEncoder().encode(record), forKey: "latestCheckout")
    }
    func undo() { record = nil; defaults.removeObject(forKey: "latestCheckout") }
}

@MainActor final class HydrationStore: ObservableObject {
    @Published private(set) var log: HydrationLog?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "waterCups"), let decoded = try? JSONDecoder().decode(HydrationLog.self, from: data) { log = try? decoded.validated() }
    }
    func drink(now: Date, settings: WorkSettings) throws {
        var value = log ?? HydrationLog(now: now, settings: settings)
        try value.add(now: now, settings: settings); log = value; persist()
    }
    func undo(now: Date, settings: WorkSettings) { log?.undoLast(now: now, settings: settings); persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(log), forKey: "waterCups") }
}

@MainActor final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status: UNAuthorizationStatus = .notDetermined
    @Published var issue: String?
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self; refresh() }
    var statusText: String {
        switch status { case .authorized, .provisional: return "通知已开启（可见性由系统控制）"; case .denied: return "通知未开启"; case .notDetermined: return "尚未授权通知"; @unknown default: return "通知状态未知" }
    }
    var authorized: Bool { status == .authorized || status == .provisional }
    func refresh() { Task { let value = await center.notificationSettings(); status = value.authorizationStatus } }
    func request() {
        guard status == .notDetermined else { openSystemSettings(); return }
        Task { do { _ = try await center.requestAuthorization(options: [.alert, .sound]); refresh() } catch { issue = "无法请求通知权限：\(error.localizedDescription)" } }
    }
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func send(id: String, title: String, body: String, sound: Bool, shouldSend: @MainActor () -> Bool = { true }) async -> String {
        let settings = await center.notificationSettings(); status = settings.authorizationStatus
        guard shouldSend() else { return "cancelled" }
        guard authorized else { return "permissionDenied" }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        if sound { content.sound = .default }
        do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)); return "submitted" }
        catch { issue = "通知发送失败：\(error.localizedDescription)"; return "failed" }
    }
    func clearPending() { center.removeAllPendingNotificationRequests() }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

@MainActor final class SpeechService: ObservableObject {
    @Published var sessionSafe = false
    private let synth = AVSpeechSynthesizer()
    var chineseVoice: AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("zh") } }
    var statusText: String { chineseVoice == nil ? "无可用中文语音，已静默降级" : !sessionSafe ? "设备锁定、睡眠或无法确认会话，语音暂停" : "系统中文语音可用" }
    func refreshSession() {
        // Read-only public Quartz session information; unknown state always suppresses speech.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool,
              let loggedIn = session[kCGSessionLoginDoneKey as String] as? Bool else { sessionSafe = false; return }
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? true
        sessionSafe = onConsole && loggedIn && !locked
    }
    func speak(_ text: String) -> String {
        refreshSession()
        guard sessionSafe else { return "sessionSuppressed" }
        guard let voice = chineseVoice else { return "voiceUnavailable" }
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = 0.45
        synth.speak(utterance); return "played"
    }
    func stop() { sessionSafe = false; synth.stopSpeaking(at: .immediate) }
}

@MainActor final class LoginService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published var issue: String?
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var statusText: String {
        switch status { case .enabled: return "已注册开机启动"; case .requiresApproval: return "需要在系统设置中允许"; case .notRegistered: return "未开启开机启动"; case .notFound: return "服务未找到，请使用固定路径的 .app"; @unknown default: return "未知注册状态" }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refresh(); issue = nil }
        catch { refresh(); issue = "开机启动失败：\(error.localizedDescription)"; throw ValidationError(issue!) }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class ReminderCoordinator: ObservableObject {
    @Published private(set) var pause: ReminderPause?
    @Published private(set) var nextEvent: ReminderEvent?
    @Published private(set) var overtimeMessage: String?
    private var checkout: CheckoutRecord?
    private var overtimeMessageDate: String?
    private var ledger: ReminderLedger
    private var timer: Timer?
    private let defaults: UserDefaults
    private let notifications: NotificationService
    private let speech: SpeechService
    private let clock: any Clock
    private var settings = WorkSettings()
    private var suspended = false
    private var planGeneration = 0
    init(notifications: NotificationService, speech: SpeechService, defaults: UserDefaults = .standard, clock: any Clock = SystemClock()) {
        self.notifications = notifications; self.speech = speech; self.defaults = defaults; self.clock = clock
        ledger = defaults.data(forKey: "reminderLedger").flatMap { try? JSONDecoder().decode(ReminderLedger.self, from: $0) } ?? ReminderLedger()
        pause = defaults.data(forKey: "reminderPause").flatMap { try? JSONDecoder().decode(ReminderPause.self, from: $0) }
        notifications.clearPending()
    }
    func configure(_ value: WorkSettings, checkout: CheckoutRecord? = nil, startup: Bool = false) {
        settings = value; self.checkout = checkout
        overtimeMessage = nil
        if !value.speechEnabled { speech.stop() }
        expirePause()
        if startup, let event = ReminderPlanner.startupEvent(now: clock.now, settings: settings, ledger: ledger, pause: pause, checkout: checkout) { deliver(event) }
        schedule()
    }
    func pauseForHour() { setPause(clock.now.addingTimeInterval(3600)) }
    func pauseUntilOffwork() {
        let work = ScheduleCalculator.snapshot(now: clock.now, settings: settings)
        if work.end > clock.now { setPause(work.end) }
    }
    private func setPause(_ until: Date) {
        pause = ReminderPause(until: until, dateKey: ScheduleCalculator.key(clock.now, calendar: settings.calendar)); persistPause(); schedule()
    }
    func resume() { pause = nil; persistPause(); schedule() }
    func expirePause() {
        if let pause, !pause.active(now: clock.now, settings: settings) { self.pause = nil; persistPause() }
        if overtimeMessageDate != ScheduleCalculator.key(clock.now, calendar: settings.calendar) { overtimeMessage = nil }
    }
    private func persistPause() { defaults.set(try? JSONEncoder().encode(pause), forKey: "reminderPause") }
    private func persistLedger() { defaults.set(try? JSONEncoder().encode(ledger), forKey: "reminderLedger") }
    func suspend() { planGeneration += 1; suspended = true; timer?.invalidate(); timer = nil; nextEvent = nil; speech.stop(); notifications.clearPending() }
    func recover() { suspended = false; notifications.clearPending(); speech.refreshSession(); expirePause(); schedule() }
    func stop() { suspend() }
    private func schedule() {
        planGeneration += 1; let generation = planGeneration
        timer?.invalidate(); timer = nil
        guard !suspended else { nextEvent = nil; return }
        expirePause()
        nextEvent = ReminderPlanner.next(now: clock.now, settings: settings, ledger: ledger, pause: pause, checkout: checkout)
        guard let event = nextEvent else { return }
        let delay = max(0.05, event.date.timeIntervalSince(clock.now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.suspended, self.planGeneration == generation else { return }
                // Late wake/fire never catches up missed events.
                if ReminderPlanner.due(event, now: self.clock.now, settings: self.settings, ledger: self.ledger, pause: self.pause, checkout: self.checkout) { self.deliver(event) }
                self.schedule()
            }
        }
        timer.tolerance = 0.2; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func content(_ event: ReminderEvent) -> (String, String) {
        if event.kind == .offwork { return ("下班啦", "下班时间到啦！点击“打卡下班”，今天辛苦了。") }
        if event.kind == .overtime {
            let work = ScheduleCalculator.snapshot(now: event.date, settings: settings)
            let message = OvertimeCalculator.message(seconds: event.date.timeIntervalSince(work.end), intervalMinutes: settings.overtimeIntervalMinutes)
            overtimeMessage = message
            overtimeMessageDate = work.dateKey
            return ("加班提醒 · 下班啦", message)
        }
        let text = HealthMessages.choose(categories: settings.categories, previous: ledger.lastMessage)
        ledger.lastMessage = text
        let hour = settings.calendar.component(.hour, from: event.date)
        let remaining = ScheduleCalculator.snapshot(now: event.date, settings: settings).remaining
        let minutes = Int(ceil(remaining / 60))
        let duration = minutes >= 60 ? "\(minutes / 60) 小时" + (minutes % 60 > 0 ? " \(minutes % 60) 分钟" : "") : "\(minutes) 分钟"
        return (String(format: "现在是 %02d:00", hour), text + "距离下班还有 \(duration)。")
    }
    private func deliver(_ event: ReminderEvent) {
        guard ledger.records[event.id] == nil else { return }
        let (title, body) = content(event)
        var record = EventRecord(notification: "reserved", speech: "skipped")
        // Reserve before any asynchronous channel so restart/permission changes cannot duplicate it.
        ledger.consume(event, record: record); persistLedger()
        if event.kind == .hourly && settings.speechEnabled { record.speech = speech.speak(title + "。" + body) }
        ledger.records[event.id] = record; persistLedger()
        let sound = settings.notificationSound
        Task {
            let outcome = await notifications.send(id: event.id, title: title, body: body, sound: sound, shouldSend: { [weak self] in
                guard let self, !self.suspended else { return false }
                return !(self.checkout?.applies(now: self.clock.now, settings: self.settings) ?? false) && ReminderPlanner.allowed(event, settings: self.settings, pause: self.pause, checkout: self.checkout)
            })
            ledger.records[event.id]?.notification = outcome; persistLedger()
        }
    }
    func test(settings testSettings: WorkSettings) {
        var text = "工作辛苦了，记得适当休息"
        if testSettings.hourlyEnabled { text = HealthMessages.choose(categories: testSettings.categories, previous: nil) }
        if testSettings.speechEnabled { _ = speech.speak("测试提醒。" + text) }
        Task { _ = await notifications.send(id: "test.\(UUID().uuidString)", title: "测试提醒", body: text, sound: testSettings.notificationSound) }
    }
}
