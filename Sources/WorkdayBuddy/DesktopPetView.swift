import SwiftUI
import AppKit
import WorkdayCore

struct DesktopPetView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: AppModel
    let openReports: () -> Void
    let openSettings: () -> Void
    @State private var petIssue: String?
    var body: some View {
        petContent.frame(width: PetPanelLayout.petSize.width, height: PetPanelLayout.petSize.height)
        .alert(model.waterIssue != nil ? L10n.text("喝水记录未保存") : L10n.text("无法切换精灵"), isPresented: Binding(get: { model.waterIssue != nil || petIssue != nil }, set: { if !$0 { model.waterIssue = nil; petIssue = nil } })) {
            Button(L10n.text("好")) { model.waterIssue = nil; petIssue = nil }
        } message: { Text(model.waterIssue ?? petIssue ?? "") }
    }
    private var petContent: some View {
        VStack(spacing: 0) {
            Button(action: openReports) {
                Text(time).font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(AssistantArt.ink)
                    .frame(width: 166, height: 44)
                    .background { PetControlImage(asset: .clock) }
            }.buttonStyle(.plain).help(timeDescription)
            PetAvatar(kind: model.settings.petKind, celebrating: model.checkout.isCheckedOut,
                      tired: model.checkout.isOvertime, animate: model.animationsActive,
                      custom: model.settings.customPet, drinkTrigger: model.drinkAnimationID,
                      animationTrigger: model.petAnimationID)
                .frame(width: 200, height: 200)
                .overlay(PetDragHandle(singleClick: model.cyclePetAnimation, doubleClick: cyclePet))
                .help(L10n.text("单击切换动作 · 双击切换形象 · 拖动移动位置"))
                .accessibilityAction(named: L10n.text("切换动作"), model.cyclePetAnimation)
                .accessibilityAction(named: L10n.text("切换精灵"), cyclePet)
                .contextMenu {
                    Button(L10n.text("下一个动作"), action: model.cyclePetAnimation)
                    Button(L10n.text("下一个精灵"), action: cyclePet)
                    Button(L10n.text("设置"), action: openSettings)
                    Button(L10n.text("退出下班啦")) { NSApp.terminate(nil) }
                }
            HStack(spacing: 18) {
                Button(action: model.drinkWater) {
                    HStack(spacing: 2) {
                        PetControlImage(asset: .cup).frame(width: 36, height: 36)
                        Text("×\(model.hydration.cups)").font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }.help(L10n.text("喝一杯水")).accessibilityLabel(L10n.text("喝一杯水"))
                    .contextMenu { Button(L10n.text("撤销上一杯"), action: model.undoWater).disabled(model.hydration.cups == 0) }
                AssistantChatButton(store: model.assistant) { model.chatVisible.toggle() }
            }.buttonStyle(.plain).foregroundStyle(AssistantArt.ink)
            PetCheckoutButton(visible: model.work.state == .after && model.checkout.canCheckout,
                              checkout: model.checkoutNow)
        }
        .padding(.top, 4).frame(width: 240, height: 330, alignment: .top)
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
                Label(L10n.text("桌面精灵陪你倒计时，可拖动和切换"), systemImage: "pawprint")
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


/// Warm paper, cocoa outlines and muted sage match the illustrated desktop controls.
enum AssistantArt {
    static let actionBlue = Color(red: 0.43, green: 0.67, blue: 0.88)
    static let ink = Color(red: 0.29, green: 0.20, blue: 0.14)
    static let paper = Color(red: 1, green: 0.96, blue: 0.86)
    static let sage = Color(red: 0.86, green: 0.91, blue: 0.81)
}

private struct AssistantChatButton: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PetControlImage(asset: .chat).frame(width: 36, height: 36)
                .frame(width: 44, height: 36).contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if !store.unreadMessageIDs.isEmpty {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(AssistantArt.paper, lineWidth: 1.5))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
        }.help(store.unreadMessageIDs.isEmpty ? L10n.text("和精灵聊聊") : L10n.text("有未读消息，点击查看"))
            .accessibilityLabel(store.unreadMessageIDs.isEmpty ? L10n.text("展开或收起聊天") : L10n.text("展开聊天，有未读消息"))
    }
}

struct AssistantChatView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    let openSettings: () -> Void
    let close: () -> Void
    var isPresented = true
    var isEnlarged = false
    var toggleSize: () -> Void = {}
    var move: (CGSize) -> Void = { _ in }
    @State private var dragPoint: NSPoint?
    @State private var draft = ""
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let point = NSEvent.mouseLocation
                if let previous = dragPoint {
                    move(CGSize(width: point.x - previous.x, height: point.y - previous.y))
                } else {
                    move(CGSize(width: value.translation.width, height: -value.translation.height))
                }
                dragPoint = point
            }
            .onEnded { _ in dragPoint = nil }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Color.clear.contentShape(Rectangle()).gesture(panelDrag)
                Button(action: toggleSize) {
                    PetControlImage(asset: isEnlarged ? .restore : .expand)
                        .frame(width: 20, height: 20)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help(L10n.text(isEnlarged ? "恢复聊天面板" : "放大聊天面板"))
                    .accessibilityLabel(L10n.text(isEnlarged ? "恢复聊天面板" : "放大聊天面板"))
                Button(action: close) {
                    PetControlImage(asset: .close).frame(width: 20, height: 20)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L10n.text("关闭对话")).accessibilityLabel(L10n.text("关闭对话"))
            }
            .frame(height: 26)
            AssistantMessagesView(store: store, isPresented: isPresented)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(panelDrag)
            if let issue = store.issue {
                Text(settingsLinkedIssue(issue)).font(.caption)
                    .tint(Color(red: 0.27, green: 0.43, blue: 0.27))
                    .fixedSize(horizontal: false, vertical: true).lineLimit(3)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.absoluteString == "workdaybuddy://assistant-settings" else { return .systemAction }
                        openSettings()
                        return .handled
                    })
            }
            if let usage = store.latestUsage, !store.isStreaming {
                Text(L10n.format("最近一次 {0} token", String(usage.totalTokens)) + (usage.cost.map { String(format: " · $%.6f", $0) } ?? ""))
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(AssistantArt.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                GrowingChatInput(text: $draft, send: send).frame(height: inputHeight)
                    .padding(7).background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AssistantArt.ink.opacity(0.25)))
                Button(action: primaryAction) {
                    PetControlImage(asset: store.isStreaming ? .stop : .send)
                        .frame(width: 32, height: 32).frame(width: 36, height: 36)
                        .opacity(!store.isStreaming && !canSend ? 0.35 : 1)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!store.isStreaming && !canSend)
                    .accessibilityLabel(store.isStreaming ? L10n.text("停止回复") : L10n.text("发送消息"))
                    .help(store.isStreaming ? L10n.text("停止回复，保留已接收内容") : L10n.text("发送消息"))
            }
        }.padding(14).foregroundStyle(AssistantArt.ink)
            .background(AssistantArt.paper, in: SketchPaperShape())
            .overlay(SketchPaperShape().stroke(AssistantArt.ink.opacity(0.55), lineWidth: 1.5))
            .shadow(color: AssistantArt.ink.opacity(0.12), radius: 3, y: 2)
    }
    private func settingsLinkedIssue(_ issue: String) -> AttributedString {
        var text = AttributedString(L10n.text(issue))
        if let range = text.range(of: L10n.text("AI 助手设置")) ?? text.range(of: "AI 助手设置") {
            text[range].link = URL(string: "workdaybuddy://assistant-settings")
            text[range].font = .system(size: 12, weight: .semibold, design: .rounded)
            text[range].underlineStyle = .single
        }
        return text
    }
    private var inputHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 14)
        let bounds = ((draft.isEmpty ? " " : draft) as NSString).boundingRect(with: NSSize(width: 235, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return min(88, max(22, ceil(bounds.height) + 5))
    }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func primaryAction() { if store.isStreaming { store.stop() } else { send() } }
    private func send() { if store.send(draft) { draft = "" } }
}

struct AssistantMessagesView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    var isPresented = true
    @State private var scrollTask: Task<Void, Never>?
    @State private var expandedMessage: AssistantMessage?
    @State private var bottomScrollRequest = 0
    @State private var earlierDays = 0
    @State private var browsingHistory = false
    @State private var loadingEarlier = false
    private var sections: [AssistantDaySection] {
        AssistantTimeline.sections(store.messages, now: store.timelineDate, calendar: store.conversationCalendar, earlierDays: earlierDays)
    }
    private var hasEarlier: Bool {
        earlierDays < AssistantTimeline.earlierDayCount(store.messages, now: store.timelineDate, calendar: store.conversationCalendar)
    }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 4) {
                if browsingHistory {
                    Button(L10n.text("回到今天")) { resetToToday(proxy) }.font(.caption)
                }
                GeometryReader { viewport in
                ScrollView {
                    // Real row heights keep streaming Markdown and the bottom anchor in sync.
                    VStack(alignment: .leading, spacing: 10) {
                        if hasEarlier {
                            Button(L10n.text("下拉查看更早的聊天记录")) { loadEarlier(proxy) }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        if sections.isEmpty {
                            Text(L10n.text("今天还没有聊天记录")).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        ForEach(sections) { section in
                            if !store.conversationCalendar.isDate(section.date, inSameDayAs: store.timelineDate) {
                                Text(AssistantTimeline.dateLabel(section.date, calendar: store.conversationCalendar))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            ForEach(section.messages) { message in
                                AssistantMessageBubble(message: message, store: store, isPresented: isPresented,
                                                       viewportHeight: viewport.size.height, expand: { expandedMessage = message }) {
                                    scheduleScroll(proxy)
                                }.id(message.id)
                            }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(2)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ChatContentHeightKey.self, value: geometry.size.height)
                        })
                        .background(HistoryPullObserver(enabled: isPresented && hasEarlier && !loadingEarlier, followLatest: isPresented && !browsingHistory, scrollRequest: bottomScrollRequest) { loadEarlier(proxy) })
                }
                }
            }
            .sheet(item: $expandedMessage) { message in
                ExpandedAssistantMessageView(store: store, messageID: message.id)
            }
            .onAppear { if isPresented { resetToToday(proxy) } }
            .onChange(of: isPresented) { visible in
                if visible { resetToToday(proxy) }
                else { scrollTask?.cancel(); scrollTask = nil }
            }
            .onChange(of: store.timelineDate) { _ in resetToToday(proxy) }
            .onChange(of: store.conversationCalendar) { _ in resetToToday(proxy) }
            .onPreferenceChange(ChatContentHeightKey.self) { _ in scheduleScroll(proxy) }
            .onChange(of: store.messages.map(\.id)) { _ in scheduleScroll(proxy) }
            .onChange(of: store.messages.last?.content) { _ in scheduleScroll(proxy) }
            .onDisappear { scrollTask?.cancel(); scrollTask = nil }
        }
    }
    private func resetToToday(_ proxy: ScrollViewProxy) {
        scrollTask?.cancel(); scrollTask = nil
        earlierDays = 0; browsingHistory = false; loadingEarlier = false
        scheduleScroll(proxy)
    }
    private func loadEarlier(_ proxy: ScrollViewProxy) {
        guard isPresented, hasEarlier, !loadingEarlier else { return }
        let anchor = sections.first?.messages.first?.id
        scrollTask?.cancel(); scrollTask = nil
        browsingHistory = true; loadingEarlier = true; earlierDays += 1
        scrollTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 32_000_000) }
            catch { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                else { proxy.scrollTo("latest", anchor: .bottom) }
            }
            loadingEarlier = false; scrollTask = nil
        }
    }
    private func scheduleScroll(_ proxy: ScrollViewProxy) {
        guard isPresented, !browsingHistory, scrollTask == nil else { return }
        scrollTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 16_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            scrollTask = nil
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { bottomScrollRequest &+= 1 }
        }
    }
}

private struct ChatContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// macOS trackpad/mouse rubber-band pull, with the button above as a keyboard-accessible alternative.
private struct HistoryPullObserver: NSViewRepresentable {
    let enabled: Bool
    let followLatest: Bool
    let scrollRequest: Int
    let pull: () -> Void
    func makeNSView(context: Context) -> PullView { PullView() }
    func updateNSView(_ view: PullView, context: Context) {
        let resumed = followLatest && !view.followLatest
        view.enabled = enabled; view.pull = pull; view.followLatest = followLatest
        if resumed || view.scrollRequest != scrollRequest {
            view.scrollRequest = scrollRequest
            view.queueBottomScroll()
        }
    }
    final class PullView: NSView {
        var enabled = false
        var followLatest = false
        var scrollRequest = 0
        var pull: (() -> Void)?
        private var token: NSObjectProtocol?
        private weak var clip: NSClipView?
        private var pulled = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token); self.token = nil }
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.observeScroll() }
        }
        func queueBottomScroll() {
            let request = scrollRequest
            DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
            // SwiftUI can restore an old scroll offset after rebuilding day sections. Reapply
            // after that layout pass, unless a newer request or history browsing superseded it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.scrollRequest == request else { return }
                self.scrollToBottom()
            }
        }
        private func scrollToBottom() {
            guard followLatest, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            scroll.layoutSubtreeIfNeeded()
            let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        private func observeScroll() {
            guard token == nil, let scroll = enclosingScrollView else { return }
            scroll.verticalScrollElasticity = .allowed
            clip = scroll.contentView
            queueBottomScroll()
            scroll.contentView.postsBoundsChangedNotifications = true
            token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.boundsChanged() }
            }
        }
        private func boundsChanged() {
            guard let clip else { return }
            if clip.bounds.minY >= 0 { pulled = false }
            guard enabled, !pulled, clip.bounds.minY < -40 else { return }
            pulled = true
            // Do not mutate SwiftUI state during the AppKit scroll layout callback.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled else { return }
                self.pull?()
            }
        }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

/// Presentation-only typing: full messages remain available to history and AI context.
private struct AssistantMessageBubble: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let message: AssistantMessage
    let store: AssistantStore
    let isPresented: Bool
    let viewportHeight: CGFloat
    let expand: () -> Void
    let didRevealText: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate: Bool?
    @State private var revealedCount = 0
    @State private var animationSource = ""
    @State private var contentHeight: CGFloat = 0
    private var user: Bool { message.role == .user }
    private var displayedText: String {
        if message.displayedContent.isEmpty { return !message.complete && store.isStreaming ? L10n.text("精灵正在想…") : L10n.text("未收到回复") }
        if user || reduceMotion || animate == false || (animate == nil && !store.needsTypingAnimation(for: message.id)) { return message.displayedContent }
        return String(message.displayedContent.prefix(max(1, revealedCount)))
    }
    var body: some View {
        HStack {
            if user { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownMessageView(source: displayedText).textSelection(.enabled)
                    if message.carryover != nil { CarryoverActionsView(store: store, messageID: message.id) }
                    if message.checklist != nil {
                        BotChecklistView(store: store, messageID: message.id)
                    }
                }.background(GeometryReader { geometry in
                    Color.clear.onAppear { contentHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { contentHeight = $0 }
                })
                if viewportHeight > 0, contentHeight + 20 > viewportHeight {
                    HStack {
                        Spacer()
                        Button(action: expand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(AssistantArt.paper, in: Circle())
                                .overlay(Circle().stroke(AssistantArt.ink.opacity(0.35), lineWidth: 1))
                        }.buttonStyle(.plain).help(L10n.text("查看完整消息"))
                            .accessibilityLabel(L10n.text("查看完整消息"))
                    }
                }
            }.font(.system(size: 13, design: .rounded))
                .padding(10).background(user ? AssistantArt.sage : .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AssistantArt.ink.opacity(0.2), lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)

            if !user { Spacer(minLength: 24) }
        }
        .task(id: message.displayedContent + (isPresented ? "visible" : "hidden")) {
            guard isPresented else { return }
            if animate == nil { animate = !user && store.takeTypingAnimation(for: message.id) }
            guard animate == true, !reduceMotion else { return }
            if !message.displayedContent.hasPrefix(animationSource) { revealedCount = 0 }
            animationSource = message.displayedContent
            let count = message.displayedContent.count
            // Catch up gently when a large SSE chunk arrives, without delaying the first character.
            while revealedCount < count {
                guard !Task.isCancelled else { return }
                revealedCount += max(1, (count - revealedCount) / 50)
                didRevealText()
                do { try await Task.sleep(nanoseconds: 20_000_000) }
                catch { return }
            }
        }
        .onChange(of: language.selection) { _ in
            animate = false
            didRevealText()
        }
    }
}

private struct ExpandedAssistantMessageView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    let messageID: UUID
    @Environment(\.dismiss) private var dismiss
    private var message: AssistantMessage? { store.messages.first { $0.id == messageID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("完整消息")).font(.headline)
                Spacer()
                Button(L10n.text("复制全部")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message?.contextContent ?? "", forType: .string)
                }
                Button(L10n.text("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let message {
                Text(message.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        MarkdownMessageView(source: message.displayedContent).textSelection(.enabled)
                        if message.carryover != nil { CarryoverActionsView(store: store, messageID: messageID) }
                        if message.checklist != nil { BotChecklistView(store: store, messageID: messageID) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }
        }.padding(20).font(.system(size: 14, design: .rounded))
            .frame(width: min(680, (NSScreen.main?.visibleFrame.width ?? 900) - 80),
                   height: min(600, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
            .environment(\.calendar, store.conversationCalendar).environment(\.timeZone, store.conversationCalendar.timeZone)
    }
}

/// Return sends; Shift-Return inserts a newline. IME composition retains native Return handling.
private struct GrowingChatInput: NSViewRepresentable {
    @Binding var text: String
    let send: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let editor = ChatTextView(); editor.delegate = context.coordinator; editor.isRichText = false
        editor.string = text
        editor.drawsBackground = false; editor.font = .systemFont(ofSize: 14)
        editor.textColor = NSColor(AssistantArt.ink); editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.textContainer?.lineFragmentPadding = 0
        editor.send = { context.coordinator.parent.send() }
        editor.compositionEnded = { [weak editor] in
            guard let editor else { return }
            context.coordinator.publishCommittedText(editor)
        }
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, !editor.hasMarkedText() else { return }
        // Native editing owns the buffer. Only external changes (e.g. successful send) replace it.
        if text != context.coordinator.lastCommittedText {
            context.coordinator.lastCommittedText = text
            if editor.string != text { editor.string = text }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingChatInput
        var lastCommittedText: String
        init(_ parent: GrowingChatInput) { self.parent = parent; lastCommittedText = parent.text }
        func publishCommittedText(_ editor: NSTextView) {
            guard !editor.hasMarkedText() else { return }
            lastCommittedText = editor.string
            if parent.text != editor.string { parent.text = editor.string }
        }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { publishCommittedText(editor) }
        }
    }
    final class ChatTextView: NSTextView {
        var send: (() -> Void)?
        var compositionEnded: (() -> Void)?
        override func unmarkText() {
            super.unmarkText()
            DispatchQueue.main.async { [weak self] in self?.compositionEnded?() }
        }
        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() { send?() }
            else { super.keyDown(with: event) }
        }
    }
}


struct SketchPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 24, y: 2))
        p.addCurve(to: CGPoint(x: w - 23, y: 3), control1: CGPoint(x: w * 0.34, y: 0), control2: CGPoint(x: w * 0.68, y: 4))
        p.addQuadCurve(to: CGPoint(x: w - 2, y: 24), control: CGPoint(x: w, y: 2))
        p.addCurve(to: CGPoint(x: w - 3, y: h - 24), control1: CGPoint(x: w - 4, y: h * 0.35), control2: CGPoint(x: w, y: h * 0.7))
        p.addQuadCurve(to: CGPoint(x: w - 24, y: h - 2), control: CGPoint(x: w, y: h))
        p.addCurve(to: CGPoint(x: 24, y: h - 3), control1: CGPoint(x: w * 0.67, y: h - 4), control2: CGPoint(x: w * 0.33, y: h))
        p.addQuadCurve(to: CGPoint(x: 3, y: h - 24), control: CGPoint(x: 1, y: h))
        p.addCurve(to: CGPoint(x: 2, y: 24), control1: CGPoint(x: 0, y: h * 0.68), control2: CGPoint(x: 4, y: h * 0.32))
        p.addQuadCurve(to: CGPoint(x: 24, y: 2), control: CGPoint(x: 0, y: 1))
        p.closeSubpath()
        return p
    }
}

private struct BotChecklistView: View {
    @ObservedObject var store: AssistantStore
    let messageID: UUID
    @State private var newItem = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("待办清单")).font(.headline)
            ForEach(store.messages.first(where: { $0.id == messageID })?.checklist?.items ?? []) { todo in
                HStack(alignment: .top) {
                    Toggle(L10n.text("完成"), isOn: Binding(get: { todo.done }, set: { _ in store.toggleChecklistItem(messageID: messageID, itemID: todo.id) }))
                        .toggleStyle(.checkbox).labelsHidden().accessibilityLabel(todo.text)
                    VStack(alignment: .leading) {
                        if todo.done {
                            Text(todo.text).strikethrough()
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(L10n.text("待办内容"), text: Binding(get: { todo.text }, set: { store.editChecklistItem(messageID: messageID, itemID: todo.id, text: $0) }), axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let due = todo.due { Text(due, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.removeChecklistItem(messageID: messageID, itemID: todo.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).accessibilityLabel(L10n.text("删除待办"))
                }
            }
            HStack {
                TextField(L10n.text("添加待办事项"), text: $newItem).onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }.accessibilityLabel(L10n.text("添加待办事项"))
                    .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(10)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }
    private func add() { store.addChecklistItem(messageID: messageID, text: newItem); newItem = "" }
}

private struct CarryoverActionsView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var store: AssistantStore
    let messageID: UUID
    private var message: AssistantMessage? { store.messages.first { $0.id == messageID } }
    var body: some View {
        if let message, message.carryover?.accepted == nil,
           store.conversationCalendar.isDate(message.date, inSameDayAs: store.timelineDate) {
            HStack(spacing: 20) {
                Button(L10n.text("是")) { store.answerCarryover(messageID: messageID, accept: true) }
                Button(L10n.text("否")) { store.answerCarryover(messageID: messageID, accept: false) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AssistantArt.actionBlue)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("是否需要创建待办事项？"))
        }
    }
}
