import SwiftUI
import UniformTypeIdentifiers
import WorkdayCore

struct CustomPetEditor: View {
    @Binding var settings: WorkSettings
    let onImport: (UUID) -> Void
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var busy = false
    @State private var issue: String?
    @State private var previewPlaying = true
    @State private var drinkTrigger = 0

    var body: some View {
        Section("自定义序列帧") {
            Button(settings.customPet == nil ? "导入 PNG 图集…" : "替换 PNG 图集…") { importing = true }.disabled(busy)
            if busy { ProgressView("正在导入…") }
            Text("一张 PNG 包含等尺寸网格帧，按从左到右、从上到下播放。建议透明背景；最大 4096×4096、32 MB、256 格。文件仅保存在本机。").font(.caption).foregroundStyle(.secondary)
            if let config = settings.customPet {
                TextField("动画名称", text: field(\.name, default: "我的伙伴"))
                Text("图集 \(config.pixelWidth) × \(config.pixelHeight) 像素").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("列数", value: field(\.columns, default: 1), format: .number)
                    TextField("行数", value: field(\.rows, default: 1), format: .number)
                }
                TextField("有效帧数（从第 1 帧开始）", value: field(\.frameCount, default: 1), format: .number)
                Stepper("速度：\(config.framesPerSecond) 帧/秒", value: field(\.framesPerSecond, default: 8), in: 1...30)
                Picker("播放方式", selection: field(\.playback, default: .loop)) {
                    ForEach(SpritePlayback.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("设置喝水动作帧", isOn: Binding(get: { settings.customPet?.drinkingFrames != nil }, set: { enabled in
                    settings.customPet?.drinkingFrames = enabled ? SpriteFrameRange(first: 1, last: max(1, config.frameCount)) : nil
                }))
                if config.drinkingFrames != nil {
                    HStack {
                        TextField("起始帧（从 1 开始）", value: drinkField(\.first), format: .number)
                        TextField("结束帧（包含）", value: drinkField(\.last), format: .number)
                    }
                }
                if let error = validationIssue(config) { Text(error).font(.caption).foregroundStyle(.red) }
                else {
                    CustomPetAvatar(config: config, animate: previewPlaying, drinkTrigger: drinkTrigger).frame(width: 150, height: 150)
                    HStack {
                        Button(previewPlaying ? "暂停预览" : "播放预览") { previewPlaying.toggle() }
                        Button("预览喝水") { previewPlaying = true; drinkTrigger += 1 }.disabled(config.drinkingFrames == nil)
                        Button("使用此动画") { settings.petKind = .custom }
                    }
                }
                Button("移除自定义动画", role: .destructive) {
                    settings.customPet = nil
                    if settings.petKind == .custom { settings.petKind = .fox }
                }
                Text("修改后点击设置窗口的“保存”生效；取消不会替换当前伙伴。").font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png]) { result in
            switch result {
            case .success(let url):
                busy = true; issue = nil
                importTask = Task {
                    do {
                        let value = try await Task.detached(priority: .userInitiated) { try CustomPetLibrary.importPNG(url) }.value
                        guard !Task.isCancelled else {
                            CustomPetLibrary.discard([value.assetID], keeping: nil)
                            return
                        }
                        onImport(value.assetID)
                        settings.customPet = value; settings.petKind = .custom
                    } catch { issue = error.localizedDescription }
                    busy = false
                }
            case .failure(let error): issue = error.localizedDescription
            }
        }
        .onDisappear { importTask?.cancel() }
    }
    private func field<T>(_ key: WritableKeyPath<CustomPetConfiguration, T>, default fallback: T) -> Binding<T> {
        Binding(get: { settings.customPet?[keyPath: key] ?? fallback }, set: { settings.customPet?[keyPath: key] = $0 })
    }
    private func drinkField(_ key: WritableKeyPath<SpriteFrameRange, Int>) -> Binding<Int> {
        Binding(get: { settings.customPet?.drinkingFrames?[keyPath: key] ?? 1 }, set: { settings.customPet?.drinkingFrames?[keyPath: key] = $0 })
    }
    private func validationIssue(_ config: CustomPetConfiguration) -> String? {
        do { _ = try config.validated(); return nil } catch { return error.localizedDescription }
    }
}
