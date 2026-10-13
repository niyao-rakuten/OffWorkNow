import Foundation
import ImageIO
import UniformTypeIdentifiers
import WorkdayCore

/// Sandboxed local copies: preferences contain only UUIDs, never arbitrary file paths.
enum CustomPetLibrary {
    // Internal override lets the smoke harness use an isolated temporary library.
    static var directory: URL = {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = support.appendingPathComponent("OffWorkNow/CustomPets", isDirectory: true)
        // Keep existing imported pets available when upgrading from the previous brand.
        let legacy = support.appendingPathComponent("XiaBanLa/CustomPets", isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return current }
        do {
            try manager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: current.path) {
                try manager.moveItem(at: legacy, to: current)
            } else {
                for file in try manager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
                    let destination = current.appendingPathComponent(file.lastPathComponent)
                    if !manager.fileExists(atPath: destination.path) {
                        try manager.copyItem(at: file, to: destination)
                    }
                }
            }
            return current
        } catch {
            // A failed migration must not make the user's existing pets disappear.
            return legacy
        }
    }()
    static func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".png") }

    static func importPNG(_ url: URL) throws -> CustomPetConfiguration {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 32 * 1024 * 1024
        guard let data = try handle.read(upToCount: limit + 1), !data.isEmpty, data.count <= limit else {
            throw ValidationError(L10n.text("请选择不超过 32 MB 的 PNG 图集"))
        }
        let dimensions = try inspect(data)
        let name = String(url.deletingPathExtension().lastPathComponent.prefix(80))
        // A single frame is safe by default; do not guess how the user's sheet is arranged.
        var value = CustomPetConfiguration(name: name.isEmpty ? L10n.text("我的伙伴") : name,
                                           pixelWidth: dimensions.0, pixelHeight: dimensions.1)
        value.automaticFrameCount = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: Self.url(for: value.assetID), options: .atomic)
        return value
    }

    static func inspect(_ data: Data) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
            throw ValidationError(L10n.text("需要有效的静态 PNG 图集，长宽不超过 4096 像素；不支持 APNG/GIF 动图"))
        }
        return (width, height)
    }

    static func validateFile(_ value: CustomPetConfiguration) throws {
        _ = try value.validated()
        guard let data = try? Data(contentsOf: url(for: value.assetID)), data.count <= 32 * 1024 * 1024 else {
            throw ValidationError(L10n.text("自定义图集已丢失，请重新导入"))
        }
        let size = try inspect(data)
        guard size.0 == value.pixelWidth, size.1 == value.pixelHeight else { throw ValidationError(L10n.text("图集尺寸已改变，请重新导入")) }
    }

    static func discard(_ ids: Set<UUID>, keeping: UUID?) {
        for id in ids where id != keeping { try? FileManager.default.removeItem(at: url(for: id)) }
    }
}

@MainActor enum CustomPetFrames {
    private final class CachedImage: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    private static let sheets: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>(); cache.countLimit = 3; cache.totalCostLimit = 128 * 1024 * 1024; return cache
    }()
    private static let cells: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>(); cache.countLimit = 256; cache.totalCostLimit = 64 * 1024 * 1024; return cache
    }()
    static func frame(_ config: CustomPetConfiguration, index: Int) -> CGImage? {
        guard (try? config.validated()) != nil, index >= 0, index < config.columns * config.rows else { return nil }
        let imageKey = config.assetID.uuidString as NSString
        let frameKey = "\(imageKey):\(config.columns):\(config.rows):\(index)" as NSString
        if let cached = cells.object(forKey: frameKey) { return cached.image }
        let sheet: CGImage
        if let cached = sheets.object(forKey: imageKey) { sheet = cached.image }
        else {
            guard let source = CGImageSourceCreateWithURL(CustomPetLibrary.url(for: config.assetID) as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  properties[kCGImagePropertyPixelWidth] as? Int == config.pixelWidth,
                  properties[kCGImagePropertyPixelHeight] as? Int == config.pixelHeight,
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            sheet = decoded
            sheets.setObject(CachedImage(sheet), forKey: imageKey, cost: sheet.width * sheet.height * 4)
        }
        guard sheet.width == config.pixelWidth, sheet.height == config.pixelHeight else { return nil }
        let width = sheet.width / config.columns, height = sheet.height / config.rows
        guard let image = sheet.cropping(to: CGRect(x: index % config.columns * width, y: index / config.columns * height, width: width, height: height)) else { return nil }
        cells.setObject(CachedImage(image), forKey: frameKey, cost: width * height * 4)
        return image
    }
}
