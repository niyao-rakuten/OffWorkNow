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
            catch { settings = WorkSettings(); recoveryMessage = L10n.text("本地配置损坏或版本不支持，已恢复默认设置。"); defaults.removeObject(forKey: "settings") }
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
    #if DEBUG
    func debugClear(dateKey: String, timeZoneID: String) {
        if record?.dateKey == dateKey && record?.timeZoneID == timeZoneID { undo() }
    }
    #endif
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
    #if DEBUG
    func debugClear(dateKey: String, timeZoneID: String) {
        guard log?.dateKey == dateKey && log?.timeZoneID == timeZoneID else { return }
        log = nil; defaults.removeObject(forKey: "waterCups")
    }
    #endif
}

@MainActor final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status: UNAuthorizationStatus = .notDetermined
    @Published var issue: String?
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self; refresh() }
    var statusText: String {
        switch status { case .authorized, .provisional: return L10n.text("通知已开启（可见性由系统控制）"); case .denied: return L10n.text("通知未开启"); case .notDetermined: return L10n.text("尚未授权通知"); @unknown default: return L10n.text("通知状态未知") }
    }
    var authorized: Bool { status == .authorized || status == .provisional }
    func refresh() { Task { let value = await center.notificationSettings(); status = value.authorizationStatus } }
    func request() {
        guard status == .notDetermined else { openSystemSettings(); return }
        Task { do { _ = try await center.requestAuthorization(options: [.alert, .sound]); refresh() } catch { issue = L10n.format("无法请求通知权限：{0}", String(describing: error.localizedDescription)) } }
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
        catch { issue = L10n.format("通知发送失败：{0}", String(describing: error.localizedDescription)); return "failed" }
    }
    func clearPending() { center.removeAllPendingNotificationRequests() }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

@MainActor final class SpeechService: ObservableObject {
    @Published var sessionSafe = false
    private let synth = AVSpeechSynthesizer()
    var chineseVoice: AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("zh") } }
    var statusText: String { chineseVoice == nil ? L10n.text("无可用中文语音，已静默降级") : !sessionSafe ? L10n.text("设备锁定、睡眠或无法确认会话，语音暂停") : L10n.text("系统中文语音可用") }
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
        switch status { case .enabled: return L10n.text("已注册开机启动"); case .requiresApproval: return L10n.text("需要在系统设置中允许"); case .notRegistered: return L10n.text("未开启开机启动"); case .notFound: return L10n.text("服务未找到，请使用固定路径的 .app"); @unknown default: return L10n.text("未知注册状态") }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refresh(); issue = nil }
        catch { refresh(); issue = L10n.format("开机启动失败：{0}", String(describing: error.localizedDescription)); throw ValidationError(issue!) }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class ReminderCoordinator: ObservableObject {
    var onMessage: (([String: String]) -> Void)?
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
    #if DEBUG
    func debugClear(dateKey: String, timeZoneID: String) {
        let marker = "." + timeZoneID + "." + dateKey
        ledger.records = ledger.records.filter { !$0.key.hasSuffix(marker) && !$0.key.contains(marker + ".") }
        if settings.timeZoneID == timeZoneID && pause?.dateKey == dateKey { pause = nil; persistPause() }
        if overtimeMessageDate == dateKey && settings.timeZoneID == timeZoneID { overtimeMessage = nil; overtimeMessageDate = nil }
        persistLedger()
    }
    #endif
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
    private func content(_ event: ReminderEvent, language: AppLanguage, healthKey: String) -> (String, String) {
        if event.kind == .offwork { return (L10n.text("下班啦", language: language), L10n.text("下班时间到啦！点击“打卡下班”，今天辛苦了。", language: language)) }
        if event.kind == .overtime {
            let work = ScheduleCalculator.snapshot(now: event.date, settings: settings)
            let message = OvertimeCalculator.message(seconds: event.date.timeIntervalSince(work.end), intervalMinutes: settings.overtimeIntervalMinutes, language: language)
            overtimeMessage = message
            overtimeMessageDate = work.dateKey
            return (L10n.text("加班提醒 · 下班啦", language: language), message)
        }
        let text = L10n.text(healthKey, language: language)
        let hour = settings.calendar.component(.hour, from: event.date)
        let remaining = ScheduleCalculator.snapshot(now: event.date, settings: settings).remaining
        let minutes = Int(ceil(remaining / 60))
        let duration = minutes >= 60 ? L10n.format("{0} 小时", String(describing: minutes / 60), language: language) + (minutes % 60 > 0 ? L10n.format(" {0} 分钟", String(describing: minutes % 60), language: language) : "") : L10n.format("{0} 分钟", String(describing: minutes), language: language)
        return (String(format: L10n.text("现在是 %02d:00", language: language), hour), text + " " + L10n.format("距离下班还有 {0}。", String(describing: duration), language: language))
    }
    private func deliver(_ event: ReminderEvent) {
        guard ledger.records[event.id] == nil else { return }
        let healthKey = event.kind == .hourly ? L10n.sourceKey(for: HealthMessages.choose(categories: settings.categories, previous: ledger.lastMessage)) : ""
        var localized: [String: String] = [:]
        for language in [AppLanguage.simplifiedChinese, .english] {
            let (title, body) = content(event, language: language, healthKey: healthKey)
            localized[language.rawValue] = title + "\n" + body
        }
        let (title, body) = content(event, language: L10n.selection.resolved(), healthKey: healthKey)
        if event.kind == .hourly { ledger.lastMessage = L10n.text(healthKey) }
        var record = EventRecord(notification: "reserved", speech: "skipped")
        // Reserve before any asynchronous channel so restart/permission changes cannot duplicate it.
        ledger.consume(event, record: record); persistLedger()
        onMessage?(localized)
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
        var text = L10n.text("工作辛苦了，记得适当休息")
        if testSettings.hourlyEnabled { text = HealthMessages.choose(categories: testSettings.categories, previous: nil) }
        if testSettings.speechEnabled { _ = speech.speak(L10n.text("测试提醒。") + text) }
        let key = L10n.sourceKey(for: text)
        onMessage?(Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map {
            ($0.rawValue, L10n.text("测试提醒", language: $0) + "\n" + L10n.text(key, language: $0))
        }))
        Task { _ = await notifications.send(id: "test.\(UUID().uuidString)", title: L10n.text("测试提醒"), body: text, sound: testSettings.notificationSound) }
    }
}

@MainActor final class AssistantStore: ObservableObject {
    @Published private(set) var unreadMessageIDs: Set<UUID> = []
    private var panelVisible = false
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { unreadMessageIDs.removeAll(); persistUnread() }
    }
    private func persistUnread() {
        defaults.set(unreadMessageIDs.map(\.uuidString), forKey: "assistant.unreadMessages")
    }
    func receive(_ localized: [String: String]) {
        var message = AssistantMessage(role: .assistant, content: localized[L10n.selection.resolved().rawValue] ?? "", proactive: true)
        message.localizedContents = localized
        unpresentedReplyIDs.insert(message.id)
        messages.append(message)
        if !panelVisible { unreadMessageIDs.insert(message.id) }
        persistUnread()
        if !isStreaming { issue = nil }
        persist()
    }
    @Published private(set) var messages: [AssistantMessage] = []
    @Published private(set) var isStreaming = false
    @Published var issue: String?
    @Published private(set) var availableModels: [AssistantModelOption] = AssistantModelOption.initialOptions
    @Published private(set) var refreshingModels = false
    @Published var modelIssue: String?
    var selectedModel: AssistantModelOption? { availableModels.first { $0.id == modelID } }
    var latestUsage: AssistantUsage? { messages.last?.usage }
    var recordedUsages: [AssistantUsage] { messages.compactMap(\.usage) }
    @Published var modelID: String { didSet { defaults.set(modelID, forKey: "assistant.model") } }
    @Published var ownerName: String { didSet { defaults.set(ownerName, forKey: "assistant.owner") } }
    private let defaults: UserDefaults
    private let historyURL: URL
    private var requestTask: Task<Void, Never>?
    private var unpresentedReplyIDs: Set<UUID> = []
    func needsTypingAnimation(for id: UUID) -> Bool { unpresentedReplyIDs.contains(id) }
    func takeTypingAnimation(for id: UUID) -> Bool {
        unpresentedReplyIDs.remove(id) != nil
    }
    func generateDailyReport(_ report: DailyReport, hideEarnings: Bool) {
        // Checkout reports are local, complete pet messages, even during another reply.
        receive(Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map {
            ($0.rawValue, report.assistantReport(hideEarnings: hideEarnings, language: $0))
        }))
    }
    var greeting: String {
        let name = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return L10n.format("Hi {0}，您有什么吩咐？", name.isEmpty || name == "主人" ? L10n.text("主人") : name)
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedModel = defaults.string(forKey: "assistant.model") ?? "nvidia/nemotron-3-super-120b-a12b:free"
        modelID = savedModel == "openrouter/free" ? "nvidia/nemotron-3-super-120b-a12b:free" : savedModel
        if savedModel == "openrouter/free" { defaults.set("nvidia/nemotron-3-super-120b-a12b:free", forKey: "assistant.model") }
        if let data = defaults.data(forKey: "assistant.models"), let models = try? JSONDecoder().decode([AssistantModelOption].self, from: data), !models.isEmpty { availableModels = models.filter { AssistantModelOption.recommendedIDs.contains($0.id) } }
        ownerName = defaults.string(forKey: "assistant.owner") ?? "主人"
        historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OffWorkNow/assistant-history.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do { messages = try AssistantHistory.load(from: historyURL) }
            catch { issue = "聊天历史读取失败：\(error.localizedDescription)" }
        }
        unreadMessageIDs = Set((defaults.stringArray(forKey: "assistant.unreadMessages") ?? []).compactMap(UUID.init(uuidString:)))
            .intersection(Set(messages.map(\.id)))
        unpresentedReplyIDs.formUnion(unreadMessageIDs)
    }
    func send(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return false }
        guard let key = AssistantCredential.read(), !key.isEmpty else { issue = "请先在 AI 助手设置中保存 OpenRouter API Key。"; return false }
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issue = "请先设置模型 ID。"; return false }
        guard let model = selectedModel else { issue = "请先在 AI 助手设置中选择可用模型。"; return false }
        let system = "你是桌面宠物 AI 助手。首先准确回答用户当前的问题，遵循用户的任务与语言；表达温和简洁，不要让角色扮演妨碍回答。用户称谓是\(String(ownerName.prefix(64)))，自然地称呼即可，无需每句重复。不能编造模型身份、能力或已经执行的操作。"
        let context: [OpenRouterMessage]
        do {
            context = try AssistantContext.build(history: messages, system: system, current: text,
                inputBudget: min(AssistantContext.maximumInputBudget, model.contextLength - AssistantContext.maximumOutputTokens - 512))
        } catch { issue = error.localizedDescription; return false }
        issue = nil
        messages.append(AssistantMessage(role: .user, content: text))
        let reply = AssistantMessage(role: .assistant, content: "", complete: false)
        unpresentedReplyIDs.insert(reply.id)
        messages.append(reply); persist(); isStreaming = true
        let request = OpenRouterRequest(model: model.id, messages: context, maxTokens: AssistantContext.maximumOutputTokens)
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isStreaming = false; self.requestTask = nil; self.persist()
            }
            do {
                let client = OpenRouterClient(configuration: .init(apiKey: key, appTitle: "WorkdayBuddy"))
                var activeRequest = request
                for attempt in 0..<2 {
                    do {
                        for try await chunk in client.stream(activeRequest) {
                            try Task.checkCancellation()
                            if let index = self.messages.firstIndex(where: { $0.id == reply.id }) {
                                if let payload = chunk.usage, let usage = AssistantUsage(payload: payload) {
                                    self.messages[index].usage = usage
                                }
                                self.messages[index].modelID = chunk.model ?? activeRequest.model
                                self.messages[index].content += chunk.choices.first(where: { $0.index == 0 })?.delta?.content ?? ""
                                self.persist()
                            }
                        }
                        try Task.checkCancellation()
                        break
                    } catch {
                        let receivedText = self.messages.first(where: { $0.id == reply.id })?.content ?? ""
                        let canFallback = attempt == 0 && model.isFree && receivedText.isEmpty && !Task.isCancelled
                        guard canFallback, AssistantRetryPolicy.shouldTryAnotherFreeModel(after: error) else { throw error }
                        let alternatives = self.availableModels.filter { $0.isFree && $0.id != model.id && AssistantModelOption.recommendedIDs.contains($0.id) }
                        let provider = model.id.split(separator: "/").first
                        guard let alternative = alternatives.first(where: { $0.id.split(separator: "/").first != provider }) ?? alternatives.first else { throw error }
                        activeRequest.model = alternative.id
                        self.issue = "所选免费模型暂时繁忙，正在尝试 \(alternative.name)…"
                    }
                }
                if let index = self.messages.firstIndex(where: { $0.id == reply.id }) {
                    if self.messages[index].content.isEmpty { self.issue = "模型没有返回文本，请换一个支持文本对话的模型再试。" }
                    else {
                        self.messages[index].complete = true; self.issue = nil
                        if !self.panelVisible {
                            self.unreadMessageIDs.insert(reply.id); self.persistUnread()
                        }
                    }
                }
            } catch is CancellationError { self.issue = "回复已停止，已保留收到的内容。" }
            catch { self.issue = "回复未完成，请稍后重试。\(error.localizedDescription)" }
        }
        return true
    }
    func refreshModels() async {
        guard !refreshingModels else { return }
        refreshingModels = true; modelIssue = nil
        defer { refreshingModels = false }
        do {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ValidationError("模型目录暂不可用") }
            let models = try AssistantModelOption.catalog(from: data)
            guard !models.isEmpty else { throw ValidationError("未找到符合预算的模型") }
            availableModels = models
            defaults.set(try JSONEncoder().encode(models), forKey: "assistant.models")
            // Preserve an existing selection; never silently switch a paid/free model.
            if selectedModel == nil { modelIssue = "原模型不在推荐列表中，请从下拉列表重新选择。" }
        } catch is CancellationError { }
        catch { modelIssue = "刷新失败，继续显示已保存的模型：\(error.localizedDescription)" }
    }
    func stop() { requestTask?.cancel() }
    #if DEBUG
    func debugClear(dateKey: String, calendar: Calendar) throws {
        guard !isStreaming else { throw ValidationError("请先停止 AI 回复，再清除数据。") }
        let next = messages.filter { ScheduleCalculator.key($0.date, calendar: calendar) != dateKey }
        try AssistantHistory.save(next, to: historyURL)
        messages = next; unpresentedReplyIDs.formIntersection(Set(next.map(\.id))); issue = nil
        unreadMessageIDs.formIntersection(Set(next.map(\.id))); persistUnread()
    }
    #endif
    private func persist() {
        do { try AssistantHistory.save(messages, to: historyURL) }
        catch { issue = "聊天历史保存失败：\(error.localizedDescription)" }
    }
    func export(to url: URL) throws { try AssistantHistory.save(messages, to: url) }
}

/// Stored only in this app's local preferences (the app container when sandboxed).
/// Never accesses the keychain, including for migration.
enum AssistantCredential {
    private static let storageKey = "assistant.apiKey"
    static func read(defaults: UserDefaults = .standard) -> String? { defaults.string(forKey: storageKey) }
    static func save(_ key: String, defaults: UserDefaults = .standard) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ValidationError("API Key 不能为空") }
        defaults.set(key, forKey: storageKey)
    }
}
