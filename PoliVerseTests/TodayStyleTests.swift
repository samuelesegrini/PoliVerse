import Foundation
import SwiftUI
import Testing
@testable import PoliVerse

/// The Oggi style survives storage and maps the weight slider to a weight.
@Suite("Today style")
struct TodayStyleTests {
    @Test("Round-trips through its stored string")
    func roundTrip() throws {
        var style = TodayStyle()
        style.dateFont = .serif
        style.dateWeight = 0.3
        style.dateAccent = .violet
        style.dateSize = 1.2
        style.greeting = .custom
        style.customGreeting = "Forza!"
        style.backgroundAccent = .green
        style.bar.showsSettings = false
        style.bar.tint = .rose
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.dateFont == style.dateFont)
        #expect(restored.dateWeight == style.dateWeight)
        #expect(restored.dateAccent == style.dateAccent)
        #expect(restored.dateSize == 1.2)
        #expect(restored.customGreeting == "Forza!")
        #expect(restored.backgroundAccent == .green)
        #expect(restored.bar == style.bar)
        #expect(restored == style)
    }

    @Test("A corrupt stored value is refused, so the default is used")
    func corrupt() {
        #expect(TodayStyle(rawValue: "not json") == nil)
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

    @Test("The background takes the date's colour unless one of its own is chosen")
    func backgroundAccentInUse() {
        var style = TodayStyle()
        style.dateAccent = .orange
        #expect(style.backgroundAccentInUse == .orange)
        style.backgroundAccent = .violet
        #expect(style.backgroundAccentInUse == .violet)
    }

    @Test("A custom greeting says what the student wrote, or the classic line while it is empty")
    func customGreeting() {
        let day = Date.now
        #expect(GreetingStyle.custom.text(for: day, firstName: nil, custom: "  Si parte  ") == "Si parte")
        #expect(GreetingStyle.custom.text(for: day, firstName: nil, custom: " ") == GreetingStyle.classic.text(for: day, firstName: nil))
    }

    @Test("Every bar button shows by default, with the app's own tint")
    func barDefaults() {
        let bar = TodayBarStyle()
        #expect(bar.showsProfile && bar.showsSettings && bar.showsAdd && bar.showsDate)
        #expect(bar.tint == nil)
        #expect(!bar.tintFollowsDate)
    }

    @Test("The controls' colour is the app's, a chosen one, or the date's; ink as the date's keeps the app's")
    func controlTint() {
        var style = TodayStyle()
        #expect(style.controlAccent == nil)
        style.bar.tint = .green
        #expect(style.controlAccent == .green)
        style.bar.tintFollowsDate = true
        style.dateAccent = .violet
        #expect(style.controlAccent == .violet)
        style.dateAccent = .ink
        #expect(style.controlAccent == nil)
    }
}
