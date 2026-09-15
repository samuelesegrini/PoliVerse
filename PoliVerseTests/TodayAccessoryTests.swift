import Foundation
import SwiftUI
import Testing
@testable import PoliVerse

/// What sits beside the date, the page's paper and grain, and the appearance.
@Suite("Today accessory, paper and appearance")
struct TodayAccessoryTests {
    @Test("A new look has plain paper, no grain, the system's appearance and nothing beside the date")
    func defaults() {
        let style = TodayStyle()
        #expect(style.paper == .plain)
        #expect(style.grain == 0)
        #expect(style.appearance == .system)
        #expect(style.accessory == .none)
    }

    @Test("Adding a sticker makes stickers the accessory")
    func stickersAccessory() {
        var style = TodayStyle()
        style.addSticker(.emoji("🎓"))
        #expect(style.accessory == .stickers)
    }

    @Test("A text accessory keeps a few words, trimmed to what fits")
    func text() {
        var style = TodayStyle()
        style.accessoryText = String(repeating: "a", count: 80)
        #expect(style.accessoryText.count == TodayStyle.accessoryTextLimit)
    }

    @Test("Photos stack up to three; the newest goes on top; their images are kept by the store")
    func photos() {
        var style = TodayStyle()
        for id in ["A", "B", "C", "D"] { style.addPhoto(id) }
        #expect(style.photoIDs == ["B", "C", "D"])
        #expect(style.accessory == .photos)
        #expect(style.storedImageIDs.isSuperset(of: ["B", "C", "D"]))
        style.removePhoto("C")
        #expect(style.photoIDs == ["B", "D"])
    }

    @Test("Grain stays between none and full")
    func grain() {
        var style = TodayStyle()
        style.grain = 3
        #expect(style.grain == 1)
        style.grain = -1
        #expect(style.grain == 0)
    }

    @Test("Everything new round-trips, and a look with the old sticker header gets the stickers accessory")
    func storage() throws {
        var style = TodayStyle()
        style.paper = .plot
        style.grain = 0.4
        style.appearance = .tinted
        style.accessory = .text
        style.accessoryText = "Tutto pronto?"
        style.addPhoto("P1")
        style.accessory = .text
        style.stickerOutline = false
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored == style)
        let legacy = try #require(TodayStyle(rawValue: #"{"header":"dateAndStickers","stickers":[]}"#))
        #expect(legacy.accessory == .stickers)
        let none = try #require(TodayStyle(rawValue: #"{"header":"date"}"#))
        #expect(none.accessory == .none)
    }

    @Test("Appearance fixes the colour scheme only for Light and Dark, and picks the Flavor mode")
    func appearance() {
        #expect(TodayAppearance.system.colorScheme == nil)
        #expect(TodayAppearance.light.colorScheme == .light)
        #expect(TodayAppearance.dark.colorScheme == .dark)
        #expect(TodayAppearance.contrast.flavorMode == .contrast)
        #expect(TodayAppearance.tinted.flavorMode == .tinted)
        #expect(TodayAppearance.system.flavorMode == .standard)
    }
}
