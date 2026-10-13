import SwiftUI
import ImageIO
import WorkdayCore

/// Imagegen originals are bundled unchanged. Calibrated atlas boundaries retain the full silhouette and source alpha.
@MainActor enum PetArtwork {
    static var resourceDirectory = Bundle.main.resourceURL?.appendingPathComponent("PetArt")
    private static var frames: [String: [CGImage]] = [:]
    private static var controls: [CGImage] = []
    private static var reportIcons: [CGImage] = []
    enum Control: Int { case cup, clock, checkout, checkedOut }

    static func frame(kind: PetKind, row: Int, column: Int) -> CGImage? {
        guard kind != .custom, (0..<6).contains(row), (0..<6).contains(column) else { return nil }
        if row == 4 || row == 5 {
            let key = kind.rawValue + (row == 4 ? "-drink" : "-music")
            if frames[key] == nil { frames[key] = loadPetFrames(key, columns: 3, rowCount: 2) }
            guard let images = frames[key], images.indices.contains(column) else { return nil }
            return images[column]
        }
        if frames[kind.rawValue] == nil { frames[kind.rawValue] = loadPetFrames(kind.rawValue) }
        let index = row * 6 + column
        guard let images = frames[kind.rawValue], images.indices.contains(index) else { return nil }
        return images[index]
    }

    static func control(_ control: Control) -> CGImage? {
        if controls.isEmpty { controls = loadCells("controls", columns: 2, rows: 2).map(trimTransparentMargin) }
        guard controls.indices.contains(control.rawValue) else { return nil }
        return controls[control.rawValue]
    }

    static func reportIcon(_ index: Int) -> CGImage? {
        if reportIcons.isEmpty { reportIcons = loadCells("report-ui", columns: 3, rows: 2).map(trimTransparentMargin) }
        return reportIcons.indices.contains(index) ? reportIcons[index] : nil
    }

    private struct AtlasRow: Decodable {
        let top: Int
        let bottom: Int
        let columns: [Int]
        let baseline: Int
        let anchors: [Anchor]?
        let scaleMultiplier: Double?
        let seam: Seam?
        struct Anchor: Decodable { let x: Double; let y: Double }
        struct Seam: Decodable { let column: Int; let y: Int; let lowerX: Int }
    }

    private static func loadPetFrames(_ name: String, columns: Int = 6, rowCount: Int = 4) -> [CGImage] {
        guard let directory = resourceDirectory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("atlas-layout.json")),
              let layout = try? JSONDecoder().decode([String: [AtlasRow]].self, from: data),
              let rows = layout[name], rows.count == rowCount,
              let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name + ".png") as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let unit = sheet.width / columns
        var result: [CGImage] = []
        for row in rows {
            guard row.columns.count == columns + 1 else { return [] }
            guard row.anchors == nil || row.anchors?.count == columns else { return [] }
            // One uniform scale per atlas; authored foot anchors remove translation without fitting each pose.
            let scale = 256.0 / Double(unit) * (row.scaleMultiplier ?? 1)
            for column in 0..<columns {
                let upperLeft = row.columns[column], upperRight = row.columns[column + 1]
                let lowerLeft = row.seam?.column == column ? row.seam!.lowerX : upperLeft
                let lowerRight = row.seam?.column == column + 1 ? row.seam!.lowerX : upperRight
                let x = min(upperLeft, lowerLeft), width = max(upperRight, lowerRight) - x
                let height = row.bottom - row.top
                guard let cell = sheet.cropping(to: CGRect(x: x, y: row.top, width: width, height: height)),
                      let context = CGContext(data: nil, width: 288, height: 288, bitsPerComponent: 8,
                                              bytesPerRow: 288 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
                // Fixed scale and column anchor, shared ground line across actions.
                // Never fit each pose's bounding box independently: it causes size pulsing.
                let anchor = row.anchors?[column]
                let left = anchor.map { 144 + (Double(x) - $0.x) * scale }
                    ?? (16 + Double(x - column * unit) * scale)
                let baseline = anchor?.y ?? Double(row.baseline)
                let top = 272 - (baseline - Double(row.top)) * scale
                if let seam = row.seam, seam.column == column || seam.column == column + 1 {
                    // A bubble and the adjacent fish's tail share a column but not a row.
                    // Follow their transparent gap rather than truncating either silhouette.
                    let points = [(upperLeft, row.top), (upperRight, row.top), (upperRight, seam.y),
                                  (lowerRight, seam.y), (lowerRight, row.bottom), (lowerLeft, row.bottom),
                                  (lowerLeft, seam.y), (upperLeft, seam.y)]
                    let path = CGMutablePath()
                    for (index, point) in points.enumerated() {
                        let p = CGPoint(x: 16 + Double(point.0 - column * unit) * scale, y: 16 + Double(row.baseline - point.1) * scale)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath(); context.addPath(path); context.clip()
                }
                context.draw(cell, in: CGRect(x: left, y: 288 - top - Double(height) * scale, width: Double(width) * scale, height: Double(height) * scale))
                guard let frame = context.makeImage() else { return [] }
                result.append(frame)
            }
        }
        return result
    }

    private static func loadCells(_ name: String, columns: Int, rows: Int) -> [CGImage] {
        guard let url = resourceDirectory?.appendingPathComponent(name + ".png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              sheet.width % columns == 0, sheet.height % rows == 0 else { return [] }
        let width = sheet.width / columns, height = sheet.height / rows
        return (0..<(columns * rows)).compactMap { index in
            sheet.cropping(to: CGRect(x: index % columns * width, y: index / columns * height, width: width, height: height))
        }
    }

    private static func trimTransparentMargin(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // The bitmap buffer and CGImage crop both use image row order.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = width, minY = height, maxX = 0, maxY = 0
            for y in 0..<height {
                for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 20 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: max(0, minX - 3), y: max(0, minY - 3),
                          width: min(width - max(0, minX - 3), maxX - minX + 7),
                          height: min(height - max(0, minY - 3), maxY - minY + 7))
        }
        return bounds.flatMap { image.cropping(to: $0) } ?? image
    }
}

struct PetControlImage: View {
    let asset: PetArtwork.Control
    var body: some View {
        if let image = PetArtwork.control(asset) {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
        }
    }
}
