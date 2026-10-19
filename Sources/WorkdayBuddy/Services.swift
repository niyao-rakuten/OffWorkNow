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
    func clearPending() {
        Task {
            let requests = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: requests.filter { !$0.identifier.hasPrefix("local.todo.") }.map(\.identifier))
        }
    }
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
    private let bot = AIBot()
    private var botContext: AIBotContext { AIBotContext(now: clock.now, settings: settings, checkout: checkout, ledger: ledger, pause: pause) }
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
        if startup { apply(bot.handle(.startup, in: botContext)) }
        schedule()
    }
    func pauseForHour() { setPause(clock.now.addingTimeInterval(3600)) }
    func pauseUntilOffwork() {
        let work = bot.inspect(botContext).work
        if work.end > clock.now { setPause(work.end) }
    }
    private func setPause(_ until: Date) {
        pause = ReminderPause(until: until, dateKey: ScheduleCalculator.key(clock.now, calendar: settings.calendar)); persistPause(); schedule()
    }
    func resume() { pause = nil; persistPause(); schedule() }
    func expirePause() {
        let state = bot.inspect(botContext)
        if pause != state.activePause { pause = state.activePause; persistPause() }
        if overtimeMessageDate != state.work.dateKey { overtimeMessage = nil }
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
        nextEvent = bot.nextReminder(in: botContext)
        guard let event = nextEvent else { return }
        let delay = max(0.05, event.date.timeIntervalSince(clock.now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.suspended, self.planGeneration == generation else { return }
                // Late wake/fire never catches up missed events.
                self.apply(self.bot.handle(.reminder(event), in: self.botContext))
                self.schedule()
            }
        }
        timer.tolerance = 0.2; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func apply(_ actions: [AIBotAction]) {
        for action in actions {
            if case .deliverReminder(let reminder) = action { deliver(reminder) }
        }
    }
    private func deliver(_ reminder: AIBotReminder) {
        let event = reminder.event
        guard ledger.records[event.id] == nil else { return }
        let text = reminder.message.text()
        let title = text.title, body = text.body
        if let key = reminder.healthMessageKey { ledger.lastMessage = key }
        if event.kind == .overtime {
            overtimeMessage = body
            overtimeMessageDate = ScheduleCalculator.key(event.date, calendar: settings.calendar)
        }
        var record = EventRecord(notification: "reserved", speech: "skipped")
        // Reserve before any asynchronous channel so restart/permission changes cannot duplicate it.
        ledger.consume(event, record: record); persistLedger()
        onMessage?(reminder.message.localizedContents)
        if reminder.speak { record.speech = speech.speak(title + ". " + body) }
        ledger.records[event.id] = record; persistLedger()
        let sound = settings.notificationSound
        Task {
            let outcome = await notifications.send(id: event.id, title: title, body: body, sound: sound, shouldSend: { [weak self] in
                guard let self, !self.suspended else { return false }
                return self.bot.mayDeliver(event, in: self.botContext)
            })
            ledger.records[event.id]?.notification = outcome; persistLedger()
        }
    }
    func test(settings testSettings: WorkSettings) {
        let message = bot.testReminder(settings: testSettings, now: clock.now)
        let text = message.text()
        if testSettings.speechEnabled { _ = speech.speak(text.title + ". " + text.body) }
        onMessage?(message.localizedContents)
        Task { _ = await notifications.send(id: message.id, title: text.title, body: text.body, sound: testSettings.notificationSound) }
    }

}

@MainActor final class AssistantStore: ObservableObject {
    @Published private(set) var timelineDate = Date()
    @Published private(set) var conversationCalendar = Calendar.current
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "assistant.weatherCity") } }
    private var startupGreetingStarted = false
    private func refreshConversationDay() {
        let now = Date(), calendar = botCalendar
        if conversationCalendar != calendar || !calendar.isDate(timelineDate, inSameDayAs: now) {
            conversationCalendar = calendar; timelineDate = now
        }
    }
    func sendStartupGreeting() async {
        guard !startupGreetingStarted else { return }
        startupGreetingStarted = true
        let date = Date(), calendar = botCalendar, name = ownerName
        let trimmed = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = trimmed.isEmpty ? "上海" : trimmed
        let day = AssistantGreetingPolicy.dayKey(now: date, calendar: calendar)
        let post = AssistantGreetingPolicy.shouldPost(messages: messages, lastPostedDay: defaults.string(forKey: "assistant.greetingDay"), now: date, calendar: calendar)
        var id: UUID?
        if post {
            receive(localBot.startupGreeting(name: name, city: city, date: date, calendar: calendar, weather: nil, pending: true), date: date)
            id = messages.last?.id
            messages[messages.count - 1].complete = false
            messages[messages.count - 1].weatherFailure = "pending"
            messages[messages.count - 1].greetingDay = day
            messages[messages.count - 1].carryover = AssistantHistory.carryoverOffer(messages, now: date, calendar: calendar)
            persist()
        }
        defaults.set(day, forKey: "assistant.greetingDay")
        let weather: StartupWeather?
        let failure: String?
        do { weather = try await StartupWeatherClient().fetch(city: city); failure = nil }
        catch { weather = nil; failure = error.localizedDescription }
        if let weather {
            var snapshots = (defaults.data(forKey: "assistant.weatherSnapshots").flatMap { try? JSONDecoder().decode([StartupWeather].self, from: $0) }) ?? []
            snapshots.append(weather)
            if let data = try? JSONEncoder().encode(Array(snapshots.suffix(365))) { defaults.set(data, forKey: "assistant.weatherSnapshots") }
        }
        defaults.set(failure, forKey: "assistant.latestWeatherFailure")
        guard let id, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let localized = localBot.startupGreeting(name: name, city: city, date: date, calendar: calendar, weather: weather)
        messages[index].weather = weather; messages[index].weatherFailure = failure
        messages[index].localizedContents = localized
        messages[index].content = localized[L10n.selection.resolved().rawValue] ?? ""
        messages[index].complete = true
        persist()
    }
    func answerCarryover(messageID: UUID, accept: Bool) {
        let previousIDs = Set(messages.map(\.id))
        guard AssistantHistory.answerCarryover(&messages, messageID: messageID, accept: accept, now: Date(), calendar: botCalendar) else { return }
        unpresentedReplyIDs.formUnion(messages.filter { !previousIDs.contains($0.id) }.map(\.id))
        persist()
    }
    @Published private(set) var todos: [BotTodo] = []
    @Published private(set) var dietEntries: [BotDietEntry] = []
    private var localTimer: Timer?
    private let localBot = AIBot()
    private var botCalendar: Calendar {
        guard let data = defaults.data(forKey: "settings"), let settings = try? SettingsCodec.decode(data) else { return .current }
        return settings.calendar
    }
    deinit { localTimer?.invalidate() }
    func editReportChecklistItem(_ report: DailyReport, itemID: UUID, text: String?, done: Bool?) -> Bool {
        guard let zone = TimeZone(identifier: report.timeZoneID) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let date = ScheduleCalculator.date(from: report.dateKey, calendar: calendar) else { return false }
        do {
            var next = messages
            let found = try AssistantHistory.editChecklistItem(&next, itemID: itemID,
                on: date, calendar: calendar, text: text, done: done)
            // An archived report can outlive its source conversation.
            guard found else { return true }
            try AssistantHistory.save(next, to: historyURL)
            messages = next; issue = nil
            return true
        } catch { issue = L10n.text("待办保存失败，请重试。"); return false }
    }
    func addChecklistItem(messageID: UUID, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        AssistantHistory.updateChecklist(&messages, messageID: messageID) { $0.items.append(BotTodo(text: text)) }
        persist()
    }
    func editChecklistItem(messageID: UUID, itemID: UUID, text: String) {
        AssistantHistory.updateChecklist(&messages, messageID: messageID) { checklist in
            guard let index = checklist.items.firstIndex(where: { $0.id == itemID }) else { return }
            checklist.items[index].text = text
        }
        persist()
    }
    func toggleChecklistItem(messageID: UUID, itemID: UUID) {
        AssistantHistory.updateChecklist(&messages, messageID: messageID) { checklist in
            guard let index = checklist.items.firstIndex(where: { $0.id == itemID }) else { return }
            checklist.items[index].done.toggle()
        }
        persist()
    }
    func removeChecklistItem(messageID: UUID, itemID: UUID) {
        AssistantHistory.updateChecklist(&messages, messageID: messageID) { $0.items.removeAll { $0.id == itemID } }
        persist()
    }
    private func saveLocal() {
        do {
            let state = LocalBotState(todos: todos, diet: dietEntries)
            defaults.set(try JSONEncoder().encode(state), forKey: "assistant.localBot")
        } catch { issue = error.localizedDescription }
    }
    private struct LocalBotState: Codable { let todos: [BotTodo]; let diet: [BotDietEntry] }
    func editTodo(_ id: UUID, text: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].text = text; saveLocal()
        scheduleTodo(todos[i])
    }
    func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle(); saveLocal(); scheduleTodo(todos[i])
    }
    func removeTodo(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["local.todo." + id.uuidString])
        todos.removeAll { $0.id == id }; saveLocal()
    }
    func addTodo(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        todos.append(BotTodo(text: value)); saveLocal()
    }
    private func scheduleTodo(_ todo: BotTodo) {
        let center = UNUserNotificationCenter.current(), id = "local.todo." + todo.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let due = todo.due, due > Date(), !todo.done, !todo.delivered else { return }
        let title = L10n.text("待办提醒"), body = todo.text
        Task {
            do {
                let settings = await center.notificationSettings()
                let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                if !authorized {
                    if settings.authorizationStatus == .notDetermined {
                        guard try await center.requestAuthorization(options: [.alert, .sound]) else { issue = L10n.text("系统通知未授权，提醒仍会在 App 运行时显示在消息面板。请在系统设置中开启通知。"); return }
                    } else { issue = L10n.text("系统通知未授权，提醒仍会在 App 运行时显示在消息面板。请在系统设置中开启通知。"); return }
                }
                guard let latest = todos.first(where: { $0.id == todo.id }), latest == todo else { return }
                let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch { issue = error.localizedDescription }
        }
    }
    private func deliverLocalReminders() {
        let due = todos.filter { !$0.done && !$0.delivered && ($0.due.map { $0 <= Date() } ?? false) }
        for todo in due {
            if let index = todos.firstIndex(where: { $0.id == todo.id }) { todos[index].delivered = true }
            receive(localizedReply("待办提醒：{0}", todo.text))
        }
        if !due.isEmpty { saveLocal() }
    }
    private func localizedReply(_ key: String, _ values: String...) -> [String: String] {
        Dictionary(uniqueKeysWithValues: [AppLanguage.simplifiedChinese, .english].map { language in
            var text = L10n.text(key, language: language)
            for (index, value) in values.enumerated() { text = text.replacingOccurrences(of: "{\(index)}", with: value) }
            return (language.rawValue, text)
        })
    }
    private func handleLocal(_ intent: LocalBotIntent, input: String) {
        messages.append(AssistantMessage(role: .user, content: input))
        switch intent {
        case .information(let request):
            fetchInformation(request)
        case .diet(let text, let date):
            dietEntries.append(BotDietEntry(date: date, text: text)); saveLocal()
            let count = dietEntries.filter { botCalendar.isDate($0.date, inSameDayAs: date) }.count
            receive(localizedReply("已记录饮食：{0}\n当天共 {1} 条记录。", text, String(count)))
        case .dietSummary(let date):
            let entries = dietEntries.filter { botCalendar.isDate($0.date, inSameDayAs: date) }
            receive(localizedReply("当天共 {0} 条饮食记录：\n{1}", String(entries.count), entries.map { "- " + $0.text }.joined(separator: "\n")))
        case .reminder(let text, let date):
            let todo = BotTodo(text: text, due: date); todos.append(todo); saveLocal(); scheduleTodo(todo)
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.timeZone = botCalendar.timeZone
            receive(localizedReply("已设置提醒：{0}\n{1}", formatter.string(from: date), text))
        case .checklist(let items):
            let existing = AssistantHistory.checklists(messages, on: Date(), calendar: botCalendar).filter { !$0.items.isEmpty }
            if items.isEmpty && !existing.isEmpty {
                for checklist in existing {
                    receive(localizedReply("待办清单"))
                    messages[messages.count - 1].checklist = checklist
                }
                persist()
                break
            }
            receive(localizedReply("已创建待办清单。"))
            messages[messages.count - 1].checklist = BotChecklist(items: items.map { BotTodo(text: $0) })
            persist()
        case .clarification(let key): receive(localizedReply(key))
        }
    }
    private func fetchInformation(_ request: BotInformationRequest) {
        let pending = BotInformationClient.status("正在获取公开资讯…", "Fetching public information…")
        var reply = AssistantMessage(role: .assistant, content: pending[L10n.selection.resolved().rawValue] ?? "", complete: false)
        reply.localizedContents = pending
        let id = reply.id
        unpresentedReplyIDs.insert(id)
        messages.append(reply); persist(); isStreaming = true
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isStreaming = false; self.requestTask = nil; self.persist() }
            let result: [String: String]
            do {
                let fetched = try await BotInformationClient().fetch(request)
                try Task.checkCancellation()
                result = fetched
            } catch {
                result = Task.isCancelled
                    ? BotInformationClient.status("资讯查询已取消。", "Information request cancelled.")
                    : BotInformationClient.status("暂时无法获取资讯，请检查网络后重试。", "Information unavailable. Check your connection and retry.")
            }
            guard let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
            self.messages[index].content = result[L10n.selection.resolved().rawValue] ?? ""
            self.messages[index].localizedContents = result
            self.messages[index].complete = !Task.isCancelled
            if !self.panelVisible { self.unreadMessageIDs.insert(id); self.persistUnread() }
        }
    }
    @Published private(set) var unreadMessageIDs: Set<UUID> = []
    private var panelVisible = false
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { unreadMessageIDs.removeAll(); persistUnread() }
    }
    private func persistUnread() {
        defaults.set(unreadMessageIDs.map(\.uuidString), forKey: "assistant.unreadMessages")
    }
    func receive(_ localized: [String: String], date: Date = Date()) {
        var message = AssistantMessage(role: .assistant, content: localized[L10n.selection.resolved().rawValue] ?? "", proactive: true, date: date)
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
    @Published var inputTokenBudget: Int { didSet { defaults.set(inputTokenBudget, forKey: "assistant.inputTokenBudget") } }
    @Published var outputTokenLimit: Int { didSet { defaults.set(outputTokenLimit, forKey: "assistant.outputTokenLimit") } }
    var effectiveTokenLimits: AssistantRequestLimits? {
        selectedModel.flatMap { try? AssistantContext.limits(for: $0, inputBudget: inputTokenBudget, outputTokens: outputTokenLimit) }
    }
    private let defaults: UserDefaults
    private let historyURL: URL
    private var requestTask: Task<Void, Never>?
    private var unpresentedReplyIDs: Set<UUID> = []
    func needsTypingAnimation(for id: UUID) -> Bool { unpresentedReplyIDs.contains(id) }
    func takeTypingAnimation(for id: UUID) -> Bool {
        unpresentedReplyIDs.remove(id) != nil
    }
    init(defaults: UserDefaults = .standard, historyURL: URL? = nil) {
        self.defaults = defaults
        weatherCity = defaults.string(forKey: "assistant.weatherCity") ?? "上海"
        let savedModel = defaults.string(forKey: "assistant.model") ?? "nvidia/nemotron-3-super-120b-a12b:free"
        modelID = savedModel == "openrouter/free" ? "nvidia/nemotron-3-super-120b-a12b:free" : savedModel
        if savedModel == "openrouter/free" { defaults.set("nvidia/nemotron-3-super-120b-a12b:free", forKey: "assistant.model") }
        if let data = defaults.data(forKey: "assistant.models"), let models = try? JSONDecoder().decode([AssistantModelOption].self, from: data) { availableModels = AssistantModelOption.restoring(models) }
        ownerName = defaults.string(forKey: "assistant.owner") ?? "主人"
        let savedInput = defaults.integer(forKey: "assistant.inputTokenBudget")
        let savedOutput = defaults.integer(forKey: "assistant.outputTokenLimit")
        inputTokenBudget = AssistantContext.inputBudgetOptions.contains(savedInput) ? savedInput : AssistantContext.defaultInputBudget
        outputTokenLimit = AssistantContext.outputTokenOptions.contains(savedOutput) ? savedOutput : AssistantContext.defaultOutputTokens
        self.historyURL = historyURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OffWorkNow/assistant-history.json")
        if FileManager.default.fileExists(atPath: self.historyURL.path) {
            do { messages = try AssistantHistory.load(from: self.historyURL) }
            catch { issue = "聊天历史读取失败：\(error.localizedDescription)" }
        }
        for index in messages.indices where messages[index].weatherFailure == "pending" {
            messages[index].complete = true; messages[index].weatherFailure = "interrupted"
            if let texts = messages[index].localizedContents {
                messages[index].localizedContents = Dictionary(uniqueKeysWithValues: texts.map { key, value in
                    let language = AppLanguage(rawValue: key) ?? .english
                    return (key, value.replacingOccurrences(of: L10n.text("正在获取天气…", language: language), with: L10n.text("天气暂不可用", language: language)))
                })
                messages[index].content = messages[index].localizedContents?[L10n.selection.resolved().rawValue] ?? messages[index].content
            }
        }
        unreadMessageIDs = Set((defaults.stringArray(forKey: "assistant.unreadMessages") ?? []).compactMap(UUID.init(uuidString:)))
            .intersection(Set(messages.map(\.id)))
        unpresentedReplyIDs.formUnion(unreadMessageIDs)
        if let data = defaults.data(forKey: "assistant.localBot") {
            do { let state = try JSONDecoder().decode(LocalBotState.self, from: data); todos = state.todos; dietEntries = state.diet }
            catch { issue = L10n.text("本地机器人数据读取失败，请保留数据并重试。") }
        }
        // Move the previous global checklist into its original reply; timed reminders stay separate.
        if !messages.contains(where: { $0.checklist != nil }),
           let index = messages.lastIndex(where: { $0.localizedContents?["zh-Hans"] == "已创建待办清单，可在下方添加、编辑和勾选事项。" || $0.content == "已创建待办清单，可在下方添加、编辑和勾选事项。" }) {
            messages[index].checklist = BotChecklist(items: todos.filter { $0.due == nil })
            messages[index].localizedContents = localizedReply("已创建待办清单。")
            messages[index].content = messages[index].localizedContents?[L10n.selection.resolved().rawValue] ?? ""
            todos.removeAll { $0.due == nil }; saveLocal(); persist()
        }
        refreshConversationDay()
        for todo in todos { scheduleTodo(todo) }
        deliverLocalReminders()
        localTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConversationDay(); self?.deliverLocalReminders() }
        }
    }
    func send(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return false }
        if let intent = localBot.interpret(text, now: Date(), calendar: botCalendar) {
            issue = nil; handleLocal(intent, input: text); return true
        }
        guard let key = AssistantCredential.read(), !key.isEmpty else { issue = "请先在 AI 助手设置中保存 OpenRouter API Key。"; return false }
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issue = "请先设置模型 ID。"; return false }
        guard let model = selectedModel else { issue = "请先在 AI 助手设置中选择可用模型。"; return false }
        let system = "你是桌面精灵 AI 助手。首先准确回答用户当前的问题，遵循用户的任务与语言；表达温和简洁，不要让角色扮演妨碍回答。用户称谓是\(String(ownerName.prefix(64)))，自然地称呼即可，无需每句重复。不能编造模型身份、能力或已经执行的操作。"
        let history = messages
        let contextCalendar = botCalendar
        let requestedInput = inputTokenBudget, requestedOutput = outputTokenLimit
        let context: [OpenRouterMessage]
        let limits: AssistantRequestLimits
        do {
            limits = try AssistantContext.limits(for: model, inputBudget: requestedInput, outputTokens: requestedOutput)
            context = try AssistantContext.build(history: history, system: system, current: text, inputBudget: limits.inputBudget, calendar: contextCalendar)
        } catch { issue = error.localizedDescription; return false }
        issue = nil
        messages.append(AssistantMessage(role: .user, content: text))
        let reply = AssistantMessage(role: .assistant, content: "", complete: false)
        unpresentedReplyIDs.insert(reply.id)
        messages.append(reply); persist(); isStreaming = true
        let request = OpenRouterRequest(model: model.id, messages: context, maxTokens: limits.outputTokens, additionalParameters: model.chatParameters)
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
                        let alternativeLimits = try AssistantContext.limits(for: alternative, inputBudget: requestedInput, outputTokens: requestedOutput)
                        activeRequest.messages = try AssistantContext.build(history: history, system: system, current: text, inputBudget: alternativeLimits.inputBudget, calendar: contextCalendar)
                        activeRequest.maxTokens = alternativeLimits.outputTokens
                        activeRequest.additionalParameters = alternative.chatParameters
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
        if defaults.string(forKey: "assistant.greetingDay") == calendar.timeZone.identifier + "/" + dateKey {
            defaults.removeObject(forKey: "assistant.greetingDay")
        }
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
