import Foundation

public enum SpritePlayback: String, Codable, CaseIterable, Sendable {
    case loop, pingPong
    public var title: String { self == .loop ? L10n.text("顺序循环") : L10n.text("往返播放") }
}

public struct SpriteFrameRange: Codable, Equatable, Hashable, Sendable {
    public var first: Int
    public var last: Int
    public init(first: Int, last: Int) { self.first = first; self.last = last }
    public var count: Int { max(0, last - first + 1) }
}

public struct CustomPetConfiguration: Codable, Equatable, Hashable, Sendable {
    public var assetID: UUID
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var columns: Int
    public var rows: Int
    public var frameCount: Int
    public var framesPerSecond: Int
    public var drinkingFrames: SpriteFrameRange? = nil
    /// Nil preserves the explicitly stored frame count in older settings.
    public var automaticFrameCount: Bool? = nil
    public var playback: SpritePlayback

    public var suggestedFrameCount: Int? {
        guard (1...32).contains(columns), (1...32).contains(rows), columns * rows <= 256,
              (1...4096).contains(pixelWidth), (1...4096).contains(pixelHeight),
              pixelWidth % columns == 0, pixelHeight % rows == 0 else { return nil }
        let total = columns * rows
        if let range = drinkingFrames {
            guard range.first >= 1, range.last >= range.first, range.last <= total else { return nil }
            if range.first > 1 { return range.first - 1 }
        }
        return total
    }

    public mutating func refreshAutomaticFrameCount() {
        if automaticFrameCount == true, let count = suggestedFrameCount { frameCount = count }
    }

    public init(assetID: UUID = UUID(), name: String, pixelWidth: Int, pixelHeight: Int,
                columns: Int = 1, rows: Int = 1, frameCount: Int = 1,
                framesPerSecond: Int = 8, playback: SpritePlayback = .loop) {
        self.assetID = assetID; self.name = name; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.columns = columns; self.rows = rows; self.frameCount = frameCount
        self.framesPerSecond = framesPerSecond; self.playback = playback
    }

    public func validated() throws -> Self {
        guard (1...4096).contains(pixelWidth), (1...4096).contains(pixelHeight) else { throw ValidationError(L10n.text("图集长宽须为 1–4096 像素")) }
        guard (1...32).contains(columns), (1...32).contains(rows), columns * rows <= 256 else { throw ValidationError(L10n.text("行列须为 1–32，总格数不能超过 256")) }
        guard pixelWidth % columns == 0, pixelHeight % rows == 0 else { throw ValidationError(L10n.text("图片宽度须能整除列数，高度须能整除行数")) }
        guard (1...(columns * rows)).contains(frameCount) else { throw ValidationError(L10n.format("有效帧数须为 1–{0}", String(describing: columns * rows))) }
        guard (1...30).contains(framesPerSecond) else { throw ValidationError(L10n.text("播放速度须为 1–30 帧/秒")) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw ValidationError(L10n.text("动画名称须为 1–80 个字符")) }
        if let drinkingFrames {
            guard drinkingFrames.first >= 1, drinkingFrames.last >= drinkingFrames.first,
                  drinkingFrames.last <= columns * rows else { throw ValidationError(L10n.text("喝水动作起止帧须在图集格数范围内（从第 1 帧开始）")) }
        }
        return self
    }

    /// Row-major frame order; ping-pong avoids duplicating either endpoint.
    public func frameIndex(elapsed: TimeInterval) -> Int {
        guard frameCount > 1, frameCount <= 256, framesPerSecond > 0, framesPerSecond <= 30,
              elapsed.isFinite, elapsed > 0 else { return 0 }
        let period = playback == .loop ? frameCount : 2 * frameCount - 2
        let phase = elapsed.truncatingRemainder(dividingBy: Double(period) / Double(framesPerSecond))
        let step = min(period - 1, Int(phase * Double(framesPerSecond)))
        return playback == .loop || step < frameCount ? step : period - step
    }
}
