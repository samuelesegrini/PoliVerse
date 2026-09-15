import Foundation
import Testing
@testable import PoliVerse

/// The looks a student finds before making any: enough variety to start
/// from, each one a sound look on its own.
@Suite("Today presets")
struct TodayPresetsTests {
    private let presets = TodayStyle.presets

    @Test("There are nine, each on a different background")
    func variety() {
        #expect(presets.count == 9)
        #expect(Set(presets.map(\.background)).count == presets.count)
        #expect(Set(presets.map(\.rawValue)).count == presets.count)
    }

    @Test("The first is the plain default, so a new student starts where the app always did")
    func firstIsDefault() {
        #expect(presets.first == TodayStyle())
    }

    @Test("Each survives storage unchanged")
    func roundTrip() throws {
        for preset in presets {
            let restored = try #require(TodayStyle(rawValue: preset.rawValue))
            #expect(restored == preset)
        }
    }

    @Test("Each has its own Flavor and typeface, and between them they show every material")
    func character() {
        #expect(Set(presets.map(\.flavor)).count == presets.count)
        #expect(Set(presets.map(\.dateFont)).count == presets.count)
        #expect(Set(presets.map(\.material)).count >= 6)
        #expect(presets.contains { $0.material == .glow })
        #expect(Set(presets.map(\.textDesign)).count == TodayStyle.TextDesign.allCases.count)
    }

    @Test("Each shows at least one section, and some use stickers, glass cards and the bar's colour")
    func contents() {
        for preset in presets {
            #expect(!preset.visibleSections.isEmpty)
            #expect(preset.stickers.count <= TodayStyle.maxStickers)
            // Presets ship without image files: emoji only.
            #expect(preset.stickerImageIDs.isEmpty)
            if !preset.stickers.isEmpty { #expect(preset.header == .dateAndStickers) }
        }
        #expect(presets.contains { !$0.stickers.isEmpty })
        #expect(presets.contains { $0.sections.contains { $0.material != nil } })
        #expect(presets.contains { !$0.bar.showsProfile || !$0.bar.showsAdd })
    }

    @Test("A student with no saved looks gets the presets")
    func library() {
        #expect(TodayStyle.library(from: "", active: TodayStyle()) == presets)
    }
}
