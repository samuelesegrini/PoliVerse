import Foundation
import SwiftUI
import Testing
@testable import PoliVerse

/// A special Flavor is kept as a name and its knobs, applied over the classic
/// fields when drawn, and forgotten quietly when a version does not know it.
@Suite("Special Flavor")
struct SpecialFlavorTests {
    @Test("Keeps its name and knobs through storage")
    func roundTrip() throws {
        var look = TodayStyle()
        look.special = .playful
        look.specialSettings.chaos = .wild
        look.specialSettings.pair = 2
        let restored = try #require(TodayStyle(rawValue: look.rawValue))
        #expect(restored.special == .playful)
        #expect(restored.specialSettings.chaos == .wild)
        #expect(restored.specialSettings.pair == 2)
        #expect(restored == look)
    }

    @Test("Stores the recipe's name, never the recipe")
    func storesOnlyTheName() throws {
        var look = TodayStyle()
        look.special = .playful
        let stored = look.rawValue
        #expect(stored.contains("\"special\":\"playful\""))
        // The classic fields stay as they were: the recipe is applied when drawn.
        let restored = try #require(TodayStyle(rawValue: stored))
        #expect(restored.dateFont == TodayStyle().dateFont)
    }

    @Test("A name this version does not know falls back to the classic look")
    func unknownName() throws {
        var look = TodayStyle()
        look.dateFont = .didot
        let stored = look.rawValue.replacingOccurrences(of: "{", with: "{\"special\":\"arcade\",", options: [], range: look.rawValue.range(of: "{"))
        let restored = try #require(TodayStyle(rawValue: stored))
        #expect(restored.special == nil)
        #expect(restored.dateFont == .didot)
        #expect(restored.resolved == restored)
    }

    @Test("A classic look is drawn as it is")
    func classicUnchanged() {
        var look = TodayStyle()
        look.dateFont = .rockwell
        look.material = .glass
        #expect(look.resolved == look)
        #expect(look.lean(0) == .zero)
    }

    @Test("Giocherelloso writes its recipe and the chosen pair")
    func playfulRecipe() {
        var look = TodayStyle()
        look.special = .playful
        look.specialSettings.pair = 1
        look.appearance = .dark
        look.name = "Mio"
        let drawn = look.resolved
        let pair = SpecialFlavor.playful.pairs[1]
        #expect(drawn.flavor.main == pair.main)
        #expect(drawn.flavor.colour(.accent) == pair.second)
        #expect(drawn.dateFont == .futura)
        #expect(drawn.material == .solid)
        #expect(drawn.paper == .dots)
        // What the student still owns is left alone.
        #expect(drawn.appearance == .dark)
        #expect(drawn.name == "Mio")
    }

    @Test("A pair out of range reads as the first")
    func pairOutOfRange() {
        var settings = SpecialSettings()
        settings.pair = 99
        #expect(SpecialFlavor.playful.pair(settings).main == SpecialFlavor.playful.pairs[0].main)
    }

    @Test("Tidy leans nothing, wild leans most")
    func lean() {
        var look = TodayStyle()
        look.special = .playful
        look.specialSettings.chaos = .tidy
        #expect(look.lean(0) == .zero)
        look.specialSettings.chaos = .wild
        #expect(abs(look.lean(0).degrees) == 4)
        #expect(look.lean(0).degrees < 0 && look.lean(1).degrees > 0)
    }

    @Test("Blueprint is always dark, monospaced, and never leans")
    func blueprintRecipe() {
        var look = TodayStyle()
        look.special = .blueprint
        look.appearance = .light
        look.specialSettings.chaos = .wild
        let drawn = look.resolved
        #expect(drawn.appearance == .dark)
        #expect(drawn.textDesign == .monospaced)
        #expect(drawn.dateFont == .mono)
        #expect(drawn.flavor.main == SpecialFlavor.blueprint.pairs[0].main)
        #expect(look.lean(0) == .zero)
    }

    @Test("Blueprint's controls read on the paper and under a white label alike")
    func blueprintControls() {
        var look = TodayStyle()
        look.special = .blueprint
        for pair in SpecialFlavor.blueprint.pairs.indices {
            look.specialSettings.pair = pair
            let drawn = look.resolved
            let control = drawn.controlAccent(dark: true)
            // UI components' threshold, both ways round.
            #expect(Flavor.contrast(control, drawn.flavor.main) >= 2.9)
            #expect(Flavor.contrast(control, .white) >= 2.9)
        }
    }

    @Test("The grid survives storage, and an older look without it reads fine")
    func gridRoundTrip() throws {
        var look = TodayStyle()
        look.special = .blueprint
        look.specialSettings.grid = .wide
        let restored = try #require(TodayStyle(rawValue: look.rawValue))
        #expect(restored.specialSettings.grid == .wide)
        let older = try #require(TodayStyle(rawValue: "{\"special\":\"blueprint\",\"specialSettings\":{\"pair\":1}}"))
        #expect(older.specialSettings.grid == .fine)
        #expect(older.specialSettings.pair == 1)
    }
}
