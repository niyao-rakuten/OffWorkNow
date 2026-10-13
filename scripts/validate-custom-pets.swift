import Foundation
import ImageIO
import WorkdayCore

@main struct CustomPetSmoke {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/custom-pet-smoke-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        CustomPetLibrary.directory = root.appendingPathComponent("library")
        let source = root.appendingPathComponent("input.png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Resources/PetArt/fox.png"), to: source)
        var config = try CustomPetLibrary.importPNG(source)
        config.columns = 6; config.rows = 4; config.frameCount = 18
        config.drinkingFrames = .init(first: 19, last: 24)
        try CustomPetLibrary.validateFile(config)
        var settings = WorkSettings(); settings.petKind = .custom; settings.customPet = config
        let restored = try SettingsCodec.decode(JSONEncoder().encode(settings))
        // Moving the originally selected file must not break the app's saved copy.
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("moved.png"))
        try CustomPetLibrary.validateFile(restored.customPet!)
        for index in 0..<24 {
            guard let image = CustomPetFrames.frame(config, index: index), image.width == 256, image.height == 256 else { fatalError("Missing custom frame \(index)") }
        }
        // A second draft must not evict or replace the currently saved library file.
        let second = try CustomPetLibrary.importPNG(root.appendingPathComponent("moved.png"))
        CustomPetLibrary.discard([config.assetID, second.assetID], keeping: config.assetID)
        guard FileManager.default.fileExists(atPath: CustomPetLibrary.url(for: config.assetID).path),
              !FileManager.default.fileExists(atPath: CustomPetLibrary.url(for: second.assetID).path) else { fatalError("Draft cleanup failed") }
        do { _ = try CustomPetLibrary.inspect(Data("not an image".utf8)); fatalError("Invalid PNG accepted") } catch is ValidationError {}
        let large = root.appendingPathComponent("large.png")
        try Data(repeating: 0, count: 32 * 1024 * 1024 + 1).write(to: large)
        do { _ = try CustomPetLibrary.importPNG(large); fatalError("Oversize PNG accepted") } catch is ValidationError {}
        CustomPetLibrary.discard([config.assetID], keeping: nil)
        do { try CustomPetLibrary.validateFile(config); fatalError("Missing file accepted") } catch is ValidationError {}
        print("PASS: PNG import, local copy after source move, settings restore, 24 frames, draft cleanup, invalid/oversize/missing files.")
    }
}
