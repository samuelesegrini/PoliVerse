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
        #expect(presets.contains { $0.sections.contains { $0.card == .glass } })
        #expect(presets.contains { $0.controlAccent != nil })
    }

    @Test("A student with no saved looks gets the presets")
    func library() {
        #expect(TodayStyle.library(from: "", active: TodayStyle()) == presets)
    }
}
