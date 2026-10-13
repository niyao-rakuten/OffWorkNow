import SwiftUI
import WorkdayCore

struct PetAvatar: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let kind: PetKind
    var celebrating = false
    var tired = false
    var animate = true
    var custom: CustomPetConfiguration? = nil
    var drinkTrigger = 0
    var animationTrigger = 0
    var body: some View {
        Group {
            if kind == .custom {
                if let custom { CustomPetAvatar(config: custom, animate: animate, drinkTrigger: drinkTrigger, animationTrigger: animationTrigger) }
                else { Text(L10n.text("请先导入动画")).font(.caption).foregroundStyle(.secondary) }
            } else {
                BuiltinPetAvatar(kind: kind, celebrating: celebrating, tired: tired, animate: animate, drinkTrigger: drinkTrigger, animationTrigger: animationTrigger)
            }
        }.id(kind).aspectRatio(1, contentMode: .fit)
    }
}

struct CustomPetAvatar: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let config: CustomPetConfiguration
    var animate = true
    var drinkTrigger = 0
    var animationTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = ProcessInfo.processInfo.systemUptime
    @State private var drinkingStarted: Double?
    private var playing: Bool { animate && !reduceMotion }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Double(max(1, min(30, config.framesPerSecond))), paused: !playing)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let frame = index(at: now)
            if let image = CustomPetFrames.frame(config, index: frame) {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            } else {
                Text(L10n.text("图集不可用，请检查设置或重新导入")).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit).accessibilityLabel(config.name)
        .onChange(of: config) { _ in started = ProcessInfo.processInfo.systemUptime; drinkingStarted = nil }
        .onChange(of: drinkTrigger) { _ in drinkingStarted = playing ? ProcessInfo.processInfo.systemUptime : nil }
        .onChange(of: animationTrigger) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let drinking = drinkingStarted.map { now - $0 < Double(config.drinkingFrames?.count ?? 0) / Double(max(1, config.framesPerSecond)) } ?? false
            drinkingStarted = playing && config.drinkingFrames != nil && !drinking ? now : nil
            started = now
        }
        .onChange(of: playing) { _ in started = ProcessInfo.processInfo.systemUptime; drinkingStarted = nil }
    }
    private func index(at now: Double) -> Int {
        guard playing else { return 0 }
        if let start = drinkingStarted, let range = config.drinkingFrames,
           now - start < Double(range.count) / Double(max(1, config.framesPerSecond)) {
            return range.first - 1 + max(0, Int((now - start) * Double(config.framesPerSecond)))
        }
        return config.frameIndex(elapsed: max(0, now - started))
    }
}

/// Six authored frames per action: four base actions, drinking, and headphone music.
struct BuiltinPetAvatar: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let kind: PetKind
    var celebrating = false
    var tired = false
    var animate = true
    var drinkTrigger = 0
    var animationTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requestedDrink = 0
    @State private var handledDrink = 0
    @State private var requestedAnimation = 0
    @State private var handledAnimation = 0
    @State private var action = 0
    @State private var started = ProcessInfo.processInfo.systemUptime

    private var playing: Bool { animate && !reduceMotion }
    private var playbackID: String { "\(kind.rawValue)-\(celebrating)-\(tired)-\(playing)-\(requestedDrink)-\(requestedAnimation)" }
    private var frameDuration: Double {
        if action == 4 { return 0.26 }
        if action == 5 { return 0.22 }
        return action == 1 && kind == .cat ? 0.28 : 0.18
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: frameDuration, paused: !playing)) { _ in
            let elapsed = playing ? max(0, ProcessInfo.processInfo.systemUptime - started) : 0
            let row = playing ? action : (celebrating ? 3 : 0)
            let frame = Int(elapsed / frameDuration) % 6
            PetSprite(kind: kind, row: row, frame: frame)
                .offset(x: kind == .goldfish && playing ? sin(ProcessInfo.processInfo.systemUptime * 0.7) * 10 : 0,
                        y: kind == .goldfish && playing ? sin(ProcessInfo.processInfo.systemUptime * 1.1) * 3 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(kind.title + (celebrating ? L10n.text("，开心下班") : tired ? L10n.text("，陪你等下班") : L10n.text("，桌面伙伴")))
        .onChange(of: drinkTrigger) { requestedDrink = $0 }
        .onChange(of: animationTrigger) { requestedAnimation = $0 }
        .task(id: playbackID) { await playActions() }
    }

    @MainActor private func playActions() async {
        if requestedAnimation != handledAnimation {
            handledAnimation = requestedAnimation
            action = (action + 1) % 6
        } else {
            action = celebrating ? 3 : (tired && kind.isOfficeWorker ? 1 : 0)
        }
        started = ProcessInfo.processInfo.systemUptime
        guard playing else { handledDrink = requestedDrink; return }
        if requestedDrink != handledDrink {
            handledDrink = requestedDrink
            action = 4
            do { try await Task.sleep(nanoseconds: 1_560_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            action = celebrating ? 3 : 0
            started = ProcessInfo.processInfo.systemUptime
        }
        while !Task.isCancelled {
            // Finish complete loops before changing poses; idle lasts longer than a small action.
            let loops = action == 0 ? Int.random(in: 3...6) : Int.random(in: 1...3)
            let duration = frameDuration * 6 * Double(loops)
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            if celebrating { action = action == 0 ? [3, 5].randomElement()! : 0 }
            else if action != 0 { action = 0 }
            else if tired && kind.isOfficeWorker { action = [1, 1, 2, 5].randomElement()! }
            else { action = [1, 2, 5].randomElement()! }
            started = ProcessInfo.processInfo.systemUptime
        }
    }
}

/// Also used by the offscreen preview tool to inspect individual authored frames.
struct PetSprite: View {
    @ObservedObject private var language = AppLanguageStore.shared
    let kind: PetKind
    var row = 0
    var frame = 0
    var body: some View {
        if let image = PetArtwork.frame(kind: kind, row: row, column: frame) {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "pawprint").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}
