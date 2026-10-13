import XCTest
@testable import WorkdayCore

final class CustomPetTests: ChineseLocalizationTestCase {
    private func sample() -> CustomPetConfiguration {
        CustomPetConfiguration(name: "自定义小狐狸", pixelWidth: 1536, pixelHeight: 1024,
                               columns: 6, rows: 4, frameCount: 24, framesPerSecond: 8)
    }
    func testLegacySettingsAndNewKindsRoundTrip() throws {
        let old = try SettingsCodec.decode(Data("{}".utf8))
        XCTAssertNil(old.customPet); XCTAssertEqual(old.petKind, .cat)
        var settings = old
        for kind in PetKind.allCases where kind != .custom {
            settings.petKind = kind
            XCTAssertEqual(try SettingsCodec.decode(JSONEncoder().encode(settings)), settings)
        }
        settings.petKind = .custom
        XCTAssertThrowsError(try settings.validated())
        settings.customPet = sample()
        settings.customPet?.drinkingFrames = SpriteFrameRange(first: 19, last: 24)
        XCTAssertEqual(try SettingsCodec.decode(JSONEncoder().encode(settings)), settings)
    }
    func testGridAndResourceLimits() throws {
        let valid = sample(); XCTAssertNoThrow(try valid.validated())
        for invalid in [0, -1, 33, Int.max] {
            var value = valid; value.columns = invalid
            XCTAssertThrowsError(try value.validated())
        }
        var value = valid; value.columns = 7
        XCTAssertThrowsError(try value.validated())
        value = valid; value.rows = 32; value.columns = 32
        XCTAssertThrowsError(try value.validated())
        value = valid; value.pixelWidth = 4097
        XCTAssertThrowsError(try value.validated())
        value = valid; value.frameCount = 25
        XCTAssertThrowsError(try value.validated())
        value = valid; value.framesPerSecond = 31
        XCTAssertThrowsError(try value.validated())
        value = valid; value.name = "  "
        XCTAssertThrowsError(try value.validated())
    }
    func testLoopAndPingPongDoNotDuplicateEndpoints() {
        var value = sample(); value.frameCount = 4; value.framesPerSecond = 1
        XCTAssertEqual((0..<9).map { value.frameIndex(elapsed: Double($0) + 0.01) }, [0,1,2,3,0,1,2,3,0])
        value.playback = .pingPong
        XCTAssertEqual((0..<9).map { value.frameIndex(elapsed: Double($0) + 0.01) }, [0,1,2,3,2,1,0,1,2])
        value.frameCount = 1
        XCTAssertEqual(value.frameIndex(elapsed: 500), 0)
        XCTAssertEqual(value.frameIndex(elapsed: .infinity), 0)
        XCTAssertEqual(value.frameIndex(elapsed: -10), 0)
    }
    func testWaterRangeMayFollowIdleFramesAndMustStayInAtlas() throws {
        var value = sample(); value.frameCount = 18
        value.drinkingFrames = SpriteFrameRange(first: 19, last: 24)
        XCTAssertNoThrow(try value.validated())
        XCTAssertEqual(value.drinkingFrames?.count, 6)
        for range in [SpriteFrameRange(first: 0, last: 2), .init(first: 20, last: 19), .init(first: 19, last: 25)] {
            value.drinkingFrames = range; XCTAssertThrowsError(try value.validated())
        }
    }
    func testSwitchCyclesBuiltinsAndIncludesCustomOnlyWhenAvailable() {
        XCTAssertEqual(PetKind.cat.next(customAvailable: false), .dog)
        XCTAssertEqual(PetKind.goldfish.next(customAvailable: false), .fox)
        XCTAssertEqual(PetKind.fox.next(customAvailable: false), .bunGirl)
        XCTAssertEqual(PetKind.bunGirl.next(customAvailable: false), .cat)
        XCTAssertEqual(PetKind.bunGirl.next(customAvailable: true), .custom)
        XCTAssertEqual(PetKind.custom.next(customAvailable: true), .cat)
        XCTAssertEqual(PetKind.custom.next(customAvailable: false), .cat)
    }

    func testImportGridAutomaticallyGrowsBeyondOneFrame() throws {
        var value = CustomPetConfiguration(name: "女生", pixelWidth: 1254, pixelHeight: 1254)
        value.automaticFrameCount = true
        value.columns = 6; value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 6)
        value.rows = 6; value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 36)
        value.drinkingFrames = .init(first: 31, last: 36); value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 30)
        XCTAssertEqual(value.frameIndex(elapsed: 0.14), 1, "Normal playback must advance beyond frame zero")
        XCTAssertEqual(value.frameIndex(elapsed: 3.64), 29)
        XCTAssertEqual(value.frameIndex(elapsed: 3.76), 0)
        XCTAssertEqual(value.drinkingFrames, .init(first: 31, last: 36))
        XCTAssertNoThrow(try value.validated())
    }

    func testLegacySingleFrameCanBeRepairedWithoutSilentlyOverwritingManualSettings() throws {
        var value = CustomPetConfiguration(name: "旧图集", pixelWidth: 1254, pixelHeight: 1254, columns: 6, rows: 6)
        value.drinkingFrames = .init(first: 31, last: 36)
        value = try JSONDecoder().decode(CustomPetConfiguration.self, from: JSONEncoder().encode(value))
        XCTAssertNil(value.automaticFrameCount)
        value.refreshAutomaticFrameCount(); XCTAssertEqual(value.frameCount, 1)
        XCTAssertEqual(value.suggestedFrameCount, 30)
        value.automaticFrameCount = true; value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 30)
        let restored = try JSONDecoder().decode(CustomPetConfiguration.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.frameCount, 30); XCTAssertEqual(restored.automaticFrameCount, true)
        value.automaticFrameCount = false; value.frameCount = 6
        value.rows = 3; value.drinkingFrames = nil; value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 6)
    }

    func testChangingOrRemovingDrinkingRangeUpdatesAutomaticCount() {
        var value = sample(); value.automaticFrameCount = true
        value.drinkingFrames = .init(first: 19, last: 24); value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 18)
        value.drinkingFrames = .init(first: 13, last: 18); value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 12)
        value.drinkingFrames = nil; value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 24)
        value.drinkingFrames = .init(first: 1, last: 6); value.refreshAutomaticFrameCount()
        XCTAssertEqual(value.frameCount, 24)
    }

    func testIncompleteGridEditsNeverOverflowOrEraseTheLastCount() {
        var value = sample(); value.automaticFrameCount = true
        for columns in [0, -1, Int.max, 7, 32] {
            value.columns = columns
            if columns == 32 { value.rows = 32 }
            XCTAssertNil(value.suggestedFrameCount)
            value.refreshAutomaticFrameCount(); XCTAssertEqual(value.frameCount, 24)
        }
        value = sample(); value.automaticFrameCount = true
        value.drinkingFrames = .init(first: 25, last: 30)
        XCTAssertNil(value.suggestedFrameCount)
        value.refreshAutomaticFrameCount(); XCTAssertEqual(value.frameCount, 24)
    }
}
