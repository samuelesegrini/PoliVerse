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
        style.showsTimetable = false
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.dateFont == style.dateFont)
        #expect(restored.dateWeight == style.dateWeight)
        #expect(restored.dateAccent == style.dateAccent)
        #expect(restored.showsTimetable == style.showsTimetable)
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
}
