import SwiftUI
import AppKit
import WorkdayCore

struct DesktopPetView: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let openAssistantSettings: () -> Void
    @State private var petIssue: String?
    @State private var chatPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
        VStack(spacing: 0) {
            Button(action: openSettings) {
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
                .accessibilityAction(named: L10n.text("切换伙伴"), cyclePet)
                .contextMenu {
                    Button(L10n.text("下一个动作"), action: model.cyclePetAnimation)
                    Button(L10n.text("下一个伙伴"), action: cyclePet)
                    Button(L10n.text("设置"), action: openSettings)
                    Button(L10n.text("退出下班啦")) { NSApp.terminate(nil) }
                }
            HStack(spacing: 18) {
                Button(action: model.drinkWater) {
                    HStack(spacing: 2) {
                        PetControlImage(asset: .cup).frame(width: 36, height: 36)
                        Text("×\(model.hydration.cups)").font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }.help("喝一杯水").accessibilityLabel("喝一杯水")
                    .contextMenu { Button("撤销上一杯", action: model.undoWater).disabled(model.hydration.cups == 0) }
                AssistantChatButton(store: model.assistant) { model.chatVisible.toggle() }
            }.buttonStyle(.plain).foregroundStyle(AssistantArt.ink)
            PetCheckoutButton(visible: model.work.state == .after && model.checkout.canCheckout,
                              checkout: model.checkoutNow)
        }
        .padding(.top, 4).frame(width: 240, height: 330, alignment: .top)
        AssistantChatView(store: model.assistant, openSettings: openAssistantSettings, close: { model.chatVisible = false }, isPresented: model.chatVisible)
            .frame(width: 344, height: 294).padding(.top, 4)
            .opacity(chatPresented ? 1 : 0)
            .allowsHitTesting(model.chatVisible)
            .accessibilityHidden(!model.chatVisible)
        }.frame(width: 600, height: 330, alignment: .topLeading)
        .onAppear { updateChatPresentation() }
        .onChange(of: model.chatVisible) { _ in updateChatPresentation() }
        .alert(model.waterIssue != nil ? L10n.text("喝水记录未保存") : L10n.text("无法切换伙伴"), isPresented: Binding(get: { model.waterIssue != nil || petIssue != nil }, set: { if !$0 { model.waterIssue = nil; petIssue = nil } })) {
            Button(L10n.text("好")) { model.waterIssue = nil; petIssue = nil }
        } message: { Text(model.waterIssue ?? petIssue ?? "") }
    }
    private func updateChatPresentation() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            chatPresented = model.chatVisible
        }
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


/// Warm paper, cocoa outlines and muted sage match the illustrated desktop controls.
enum AssistantArt {
    static let ink = Color(red: 0.29, green: 0.20, blue: 0.14)
    static let paper = Color(red: 1, green: 0.96, blue: 0.86)
    static let sage = Color(red: 0.86, green: 0.91, blue: 0.81)
}

private struct AssistantChatButton: View {
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
        }.help(store.unreadMessageIDs.isEmpty ? "和小宠物聊聊" : "有未读消息，点击查看")
            .accessibilityLabel(store.unreadMessageIDs.isEmpty ? "展开或收起聊天" : "展开聊天，有未读消息")
    }
}

struct AssistantChatView: View {
    @ObservedObject var store: AssistantStore
    let openSettings: () -> Void
    let close: () -> Void
    var isPresented = true
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("小宠物的悄悄话").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: close) {
                    PetControlImage(asset: .close).frame(width: 20, height: 20)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).help("关闭对话").accessibilityLabel("关闭对话")
            }
            AssistantMessagesView(store: store, isPresented: isPresented)
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
                Text("最近一次 \(usage.totalTokens) token" + (usage.cost.map { String(format: " · $%.6f", $0) } ?? ""))
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
                    .accessibilityLabel(store.isStreaming ? "停止回复" : "发送消息")
                    .help(store.isStreaming ? "停止回复，保留已接收内容" : "发送消息")
            }
        }.padding(14).foregroundStyle(AssistantArt.ink)
            .background(AssistantArt.paper, in: SketchPaperShape())
            .overlay(SketchPaperShape().stroke(AssistantArt.ink.opacity(0.55), lineWidth: 1.5))
            .shadow(color: AssistantArt.ink.opacity(0.12), radius: 3, y: 2)
    }
    private func settingsLinkedIssue(_ issue: String) -> AttributedString {
        var text = AttributedString(issue)
        if let range = text.range(of: "AI 助手设置") {
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
    @ObservedObject var store: AssistantStore
    var isPresented = true
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    bubble(store.greeting, user: false)
                    ForEach(store.messages) { message in
                        AssistantMessageBubble(message: message, store: store, isPresented: isPresented) {
                            proxy.scrollTo("latest", anchor: .bottom)
                        }.id(message.id)
                    }
                    Color.clear.frame(height: 1).id("latest")
                }.padding(2)
            }
            .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
            .onChange(of: isPresented) { visible in
                if visible { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: store.messages) { _ in proxy.scrollTo("latest", anchor: .bottom) }
        }
    }
    private func bubble(_ text: String, user: Bool) -> some View {
        HStack {
            if user { Spacer(minLength: 24) }
            Text(text).font(.system(size: 13, design: .rounded)).textSelection(.enabled)
                .padding(10).background(user ? AssistantArt.sage : .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AssistantArt.ink.opacity(0.2), lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
            if !user { Spacer(minLength: 24) }
        }
    }
}

/// Presentation-only typing: full messages remain available to history and AI context.
private struct AssistantMessageBubble: View {
    let message: AssistantMessage
    let store: AssistantStore
    let isPresented: Bool
    let didRevealText: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate: Bool?
    @State private var revealedCount = 0
    private var user: Bool { message.role == .user }
    private var displayedText: String {
        if message.content.isEmpty { return !message.complete && store.isStreaming ? "小宠物正在想…" : "未收到回复" }
        if user || reduceMotion || animate == false || (animate == nil && !store.needsTypingAnimation(for: message.id)) { return message.content }
        return String(message.content.prefix(max(1, revealedCount)))
    }
    var body: some View {
        HStack {
            if user { Spacer(minLength: 24) }
            Text(displayedText).font(.system(size: 13, design: .rounded)).textSelection(.enabled)
                .padding(10).background(user ? AssistantArt.sage : .white.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AssistantArt.ink.opacity(0.2), lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(message.content.isEmpty ? displayedText : message.content)
            if !user { Spacer(minLength: 24) }
        }
        .task(id: message.content + (isPresented ? "visible" : "hidden")) {
            guard isPresented else { return }
            if animate == nil { animate = !user && store.takeTypingAnimation(for: message.id) }
            guard animate == true, !reduceMotion else { return }
            let count = message.content.count
            // Catch up gently when a large SSE chunk arrives, without delaying the first character.
            while revealedCount < count {
                guard !Task.isCancelled else { return }
                revealedCount += max(1, (count - revealedCount) / 50)
                didRevealText()
                do { try await Task.sleep(nanoseconds: 20_000_000) }
                catch { return }
            }
        }
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
