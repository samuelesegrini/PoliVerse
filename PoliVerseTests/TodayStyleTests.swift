import Foundation
import SwiftUI
import Testing
@testable import PoliVerse

/// The Oggi style survives storage, maps the weight slider to a weight, and
/// carries looks saved by older versions into the Flavor and Material model.
@Suite("Today style")
struct TodayStyleTests {
    @Test("Round-trips through its stored string")
    func roundTrip() throws {
        var style = TodayStyle()
        style.dateFont = .didot
        style.dateWeight = 0.3
        style.dateColour = .flavor
        style.flavor = try #require(Flavor(hex: "#C2386F"))
        style.material = .glow
        style.textDesign = .serif
        style.dateSize = 1.2
        style.greeting = .custom
        style.customGreeting = "Forza!"
        style.bar.showsProfile = false
        style.updateSection(.upcoming) { $0.material = .tintedGlass }
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.dateFont == .didot)
        #expect(restored.flavor == style.flavor)
        #expect(restored.dateColour == .flavor)
        #expect(restored.material == .glow)
        #expect(restored.textDesign == .serif)
        #expect(restored.dateSize == 1.2)
        #expect(restored.customGreeting == "Forza!")
        #expect(restored.bar == style.bar)
        #expect(restored.section(.upcoming)?.material == .tintedGlass)
        #expect(restored == style)
    }

    @Test("A corrupt stored value is refused, so the default is used")
    func corrupt() {
        #expect(TodayStyle(rawValue: "not json") == nil)
    }

    @Test("A new look is ink on the Politecnico's blue, soft cards, the system's text")
    func defaults() {
        let style = TodayStyle()
        #expect(style.flavor == .polimi)
        #expect(style.dateColour == .ink)
        #expect(style.material == .soft)
        #expect(style.textDesign == .standard)
    }

    @Test("The app's accent colour is always the Flavor's readable accent, in both modes")
    func controlsFollowFlavor() throws {
        var style = TodayStyle()
        style.flavor = try #require(Flavor(hex: "#FFD60A"))
        for dark in [false, true] {
            #expect(style.controlAccent(dark: dark) == style.flavor.accent(dark: dark))
        }
    }

    @Test("The slider ends are regular and black")
    func weightEnds() {
        var style = TodayStyle()
        style.dateWeight = 0
        #expect(style.weight == .regular)
        style.dateWeight = 1
        #expect(style.weight == .black)
    }

    @Test("The date size stays within what fits beside the stickers and on a card")
    func dateSize() {
        var style = TodayStyle()
        style.dateSize = 5
        #expect(style.dateSize == TodayStyle.dateSizes.upperBound)
        style.dateSize = 0
        #expect(style.dateSize == TodayStyle.dateSizes.lowerBound)
    }

    @Test("A custom greeting says what the student wrote, or the classic line while it is empty")
    func customGreeting() {
        let day = Date.now
        #expect(GreetingStyle.custom.text(for: day, firstName: nil, custom: "  Si parte  ") == "Si parte")
        #expect(GreetingStyle.custom.text(for: day, firstName: nil, custom: " ") == GreetingStyle.classic.text(for: day, firstName: nil))
    }

    @Test("A section draws in its own material, or the page's when it has none")
    func sectionMaterial() {
        var style = TodayStyle()
        style.material = .frosted
        #expect(style.material(for: style.section(.upcoming)!) == .frosted)
        style.updateSection(.upcoming) { $0.material = .bare }
        #expect(style.material(for: style.section(.upcoming)!) == .bare)
    }

    // MARK: Older looks

    @Test("A coloured date from before Flavor becomes that Flavor, and the date keeps its colour")
    func legacyDateAccent() throws {
        let style = try #require(TodayStyle(rawValue: #"{"dateAccent":"orange"}"#))
        #expect(style.flavor == TodayStyle.legacyFlavor("orange"))
        #expect(style.dateColour == .flavor)
    }

    @Test("An ink date keeps ink; the background's colour, else the controls', becomes the Flavor")
    func legacyInk() throws {
        let background = try #require(TodayStyle(rawValue: #"{"dateAccent":"ink","backgroundAccent":"green","bar":{"tint":"rose"}}"#))
        #expect(background.dateColour == .ink)
        #expect(background.flavor == TodayStyle.legacyFlavor("green"))
        let controls = try #require(TodayStyle(rawValue: #"{"bar":{"tintFollowsDate":true},"dateAccent":"violet"}"#))
        #expect(controls.flavor == TodayStyle.legacyFlavor("violet"))
        let plain = try #require(TodayStyle(rawValue: #"{"dateFont":"serif"}"#))
        #expect(plain.flavor == .polimi)
        #expect(plain.dateColour == .ink)
    }

    @Test("A section's old card becomes its material: glass stays glass, plain is bare, filled follows the page")
    func legacyCards() throws {
        let style = try #require(TodayStyle(rawValue:
            #"{"sections":[{"kind":"upcoming","card":"glass"},{"kind":"timetable","card":"plain"},{"kind":"exams","card":"filled"}]}"#))
        #expect(style.section(.upcoming)?.material == .glass)
        #expect(style.section(.timetable)?.material == .bare)
        #expect(style.section(.exams)?.material == nil)
    }

    @Test("The bar keeps settings and Personalizza always; older looks' add and settings toggles are read and dropped")
    func barAlwaysReachable() throws {
        let bar = TodayBarStyle()
        #expect(bar.showsProfile && bar.showsDate)
        let legacy = try #require(TodayStyle(rawValue: #"{"bar":{"showsSettings":false,"showsAdd":false,"showsProfile":false}}"#))
        #expect(!legacy.bar.showsProfile)
        #expect(legacy.bar.showsDate)
        #expect(!legacy.rawValue.contains("showsSettings"))
        #expect(!legacy.rawValue.contains("showsAdd"))
    }
}
