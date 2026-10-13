import SwiftUI
import AppKit
import WorkdayCore
import ImageIO
import UniformTypeIdentifiers

@main struct PetPreviewTool {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        PetArtwork.resourceDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/PetArt")
        for kind in PetKind.allCases.filter { $0 != .custom } {
            for row in 0..<6 {
                for frame in 0..<6 {
                    guard let image = PetArtwork.frame(kind: kind, row: row, column: frame), image.width == 288, image.height == 288 else {
                        throw NSError(domain: "Missing sprite \(kind.rawValue)/\(row)/\(frame)", code: 1)
                    }
                }
            }
        }
        for control in [PetArtwork.Control.cup, .clock, .checkout, .checkedOut] {
            guard let image = PetArtwork.control(control) else { throw NSError(domain: "Missing UI image", code: 2) }
            print("Control \(control): \(image.width) × \(image.height)")
        }
        for dark in [false, true] {
            let renderer = ImageRenderer(content: preview(dark: dark, row: 0, frame: 0))
            renderer.scale = 2
            guard let cgImage = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { throw NSError(domain: "PetPreview", code: 3) }
            try data.write(to: URL(fileURLWithPath: "docs/assets/pets-\(dark ? "dark" : "light").png"))
        }
        for row in 1..<6 {
            let renderer = ImageRenderer(content: preview(dark: true, row: row, frame: 3))
            renderer.scale = 2
            if let cgImage = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: "build/pets-action-\(row).png"))
            }
        }
        // Authored frames rendered through the same SwiftUI components, exported for visual review.
        let url = URL(fileURLWithPath: "docs/assets/pets-actions.gif")
        guard let gif = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 36, nil) else { return }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for row in 0..<6 {
            for frame in 0..<6 {
                let renderer = ImageRenderer(content: preview(dark: false, row: row, frame: frame))
                guard let image = renderer.cgImage else { continue }
                CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.22]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "GIF export", code: 4) }
        for (name, rows) in [("bun-girl-actions", Array(0..<6)), ("fox-actions", Array(0..<6)), ("pets-drinking", [4]), ("pets-music", [5])] {
            let destination = URL(fileURLWithPath: "docs/assets/\(name).gif")
            guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, rows.count * 6, nil) else { continue }
            CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for row in rows {
                for frame in 0..<6 {
                    let cg: CGImage?
                    if name == "fox-actions" || name == "bun-girl-actions" {
                        cg = ImageRenderer(content: PetSprite(kind: name == "bun-girl-actions" ? .bunGirl : .fox, row: row, frame: frame)
                            .frame(width: 280, height: 280).padding(20).background(Color(red: 0.95, green: 0.94, blue: 0.90))).cgImage
                    } else { cg = ImageRenderer(content: preview(dark: false, row: row, frame: frame)).cgImage }
                    if let cg { CGImageDestinationAddImage(output, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.26]] as CFDictionary) }
                }
            }
            guard CGImageDestinationFinalize(output) else { throw NSError(domain: "Action GIF export", code: 5) }
        }
        print("Validated \(PetKind.allCases.filter { $0 != .custom }.count * 36) frames and 4 controls; rendered light/dark UI and animation preview.")
    }

    @MainActor private static func preview(dark: Bool, row: Int, frame: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(PetKind.allCases.filter { $0 != .custom }, id: \.self) { kind in
                VStack(spacing: 0) {
                    PetControls(time: kind == .worker ? "+00:15:32" : kind == .dog ? "00:00:00" : kind == .goldfish ? "✓ 18:01" : "02:35:18", timeDescription: "倒计时",
                                cups: kind == .goldfish ? 6 : 3, cupVolume: 500, totalML: 1500,
                                overtime: kind == .worker,
                                openSettings: {}, drink: {}, undoDrink: {})
                    PetSprite(kind: kind, row: row, frame: frame).frame(width: 200, height: 200)
                    PetCheckoutButton(visible: kind == .worker || kind == .dog, checkout: {})
                }.frame(width: 240, height: 290, alignment: .top)
            }
        }
        .padding(24)
        .background(dark ? Color(red: 0.15, green: 0.19, blue: 0.23) : Color(red: 0.94, green: 0.95, blue: 0.91))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
