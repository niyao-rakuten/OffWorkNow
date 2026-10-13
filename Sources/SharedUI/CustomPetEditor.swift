import SwiftUI
import UniformTypeIdentifiers
import WorkdayCore

struct CustomPetEditor: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @Binding var settings: WorkSettings
    let onImport: (UUID) -> Void
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var busy = false
    @State private var issue: String?
    @State private var previewPlaying = true
    @State private var drinkTrigger = 0

    var body: some View {
        Section(L10n.text("自定义序列帧")) {
            Button(settings.customPet == nil ? L10n.text("导入 PNG 图集…") : L10n.text("替换 PNG 图集…")) { importing = true }.disabled(busy)
            if busy { ProgressView(L10n.text("正在导入…")) }
            Text(L10n.text("一张 PNG 包含等尺寸网格帧，按从左到右、从上到下播放。建议透明背景；最大 4096×4096、32 MB、256 格。文件仅保存在本机。")).font(.caption).foregroundStyle(.secondary)
            if let config = settings.customPet {
                TextField(L10n.text("动画名称"), text: field(\.name, default: L10n.text("我的伙伴")))
                Text(L10n.format("图集 {0} × {1} 像素", String(describing: config.pixelWidth), String(describing: config.pixelHeight))).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(L10n.text("列数"), value: field(\.columns, default: 1), format: .number)
                    TextField(L10n.text("行数"), value: field(\.rows, default: 1), format: .number)
                }
                Toggle(L10n.text("自动计算普通动画帧数"), isOn: Binding(get: { settings.customPet?.automaticFrameCount == true }, set: { enabled in
                    update { $0.automaticFrameCount = enabled }
                }))
                TextField(L10n.text("普通动画帧数（从第 1 帧开始）"), value: field(\.frameCount, default: 1), format: .number)
                    .disabled(config.automaticFrameCount == true)
                Text(L10n.text("自动模式播放全部网格；设置喝水起始帧后，普通动画播放它之前的帧。需要固定帧数时可关闭自动模式。")).font(.caption).foregroundStyle(.secondary)
                if config.frameCount == 1, let suggested = config.suggestedFrameCount, suggested > 1 {
                    Text(L10n.text("当前普通动画只有 1 帧，因此会停在第一张图；喝水动画使用独立帧段。")).font(.caption).foregroundStyle(.orange)
                    Button(L10n.format("自动修正为 {0} 帧并播放", String(describing: suggested))) {
                        update { $0.automaticFrameCount = true }
                        previewPlaying = true
                    }
                }
                Stepper(L10n.format("速度：{0} 帧/秒", String(describing: config.framesPerSecond)), value: field(\.framesPerSecond, default: 8), in: 1...30)
                Picker(L10n.text("播放方式"), selection: field(\.playback, default: .loop)) {
                    ForEach(SpritePlayback.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(L10n.text("设置喝水动作帧"), isOn: Binding(get: { settings.customPet?.drinkingFrames != nil }, set: { enabled in
                    update { value in
                        if enabled, (1...32).contains(value.columns), (1...32).contains(value.rows), value.columns * value.rows <= 256 {
                            let total = value.columns * value.rows
                            value.drinkingFrames = SpriteFrameRange(first: max(1, total - value.columns + 1), last: total)
                        } else { value.drinkingFrames = nil }
                    }
                }))
                if config.drinkingFrames != nil {
                    Text(L10n.text("开启时默认使用最后一行，请按实际图集确认喝水范围。")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField(L10n.text("起始帧（从 1 开始）"), value: drinkField(\.first), format: .number)
                        TextField(L10n.text("结束帧（包含）"), value: drinkField(\.last), format: .number)
                    }
                }
                if let error = validationIssue(config) { Text(error).font(.caption).foregroundStyle(.red) }
                else {
                    Text(L10n.format("普通动画：第 1–{0} 帧", String(describing: config.frameCount)) + (config.drinkingFrames.map { L10n.format(" · 喝水：第 {0}–{1} 帧", String(describing: $0.first), String(describing: $0.last)) } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    CustomPetAvatar(config: config, animate: previewPlaying, drinkTrigger: drinkTrigger).frame(width: 150, height: 150)
                    HStack {
                        Button(previewPlaying ? L10n.text("暂停预览") : L10n.text("播放预览")) { previewPlaying.toggle() }
                        Button(L10n.text("预览喝水")) { previewPlaying = true; drinkTrigger += 1 }.disabled(config.drinkingFrames == nil)
                        Button(L10n.text("使用此动画")) { settings.petKind = .custom }
                    }
                }
                Button(L10n.text("移除自定义动画"), role: .destructive) {
                    settings.customPet = nil
                    if settings.petKind == .custom { settings.petKind = .fox }
                }
                Text(L10n.text("修改后点击设置窗口的“保存”生效；取消不会替换当前伙伴。")).font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png]) { result in
            switch result {
            case .success(let url):
                busy = true; issue = nil
                importTask = Task {
                    defer { busy = false }
                    do {
                        let value = try await Task.detached(priority: .userInitiated) { try CustomPetLibrary.importPNG(url) }.value
                        guard !Task.isCancelled else {
                            CustomPetLibrary.discard([value.assetID], keeping: nil)
                            return
                        }
                        onImport(value.assetID)
                        settings.customPet = value; settings.petKind = .custom
                    } catch { issue = error.localizedDescription }
                }
            case .failure(let error): issue = error.localizedDescription
            }
        }
        .onDisappear { importTask?.cancel() }
    }
    private func field<T>(_ key: WritableKeyPath<CustomPetConfiguration, T>, default fallback: T) -> Binding<T> {
        Binding(get: { settings.customPet?[keyPath: key] ?? fallback }, set: { value in update { $0[keyPath: key] = value } })
    }
    private func drinkField(_ key: WritableKeyPath<SpriteFrameRange, Int>) -> Binding<Int> {
        Binding(get: { settings.customPet?.drinkingFrames?[keyPath: key] ?? 1 }, set: { value in update { $0.drinkingFrames?[keyPath: key] = value } })
    }
    private func update(_ change: (inout CustomPetConfiguration) -> Void) {
        guard var config = settings.customPet else { return }
        change(&config)
        config.refreshAutomaticFrameCount()
        settings.customPet = config
    }
    private func validationIssue(_ config: CustomPetConfiguration) -> String? {
        do { _ = try config.validated(); return nil } catch { return error.localizedDescription }
    }
}
