import Foundation
import Testing
@testable import PoliVerse

/// The page's sheet: one choice, whether it is a paper texture or a decoration
/// in the Flavor's colour.
@Suite("Page sheet")
struct TodaySheetTests {
    @Test("A new look is on plain paper, with no decoration")
    func plain() {
        let style = TodayStyle()
        #expect(style.sheet == .paper(.plain))
        #expect(TodaySheet.all.first == .paper(.plain))
    }

    @Test("Choosing a decoration puts the paper back to plain, and the other way round")
    func oneOrTheOther() {
        var style = TodayStyle()
        style.sheet = .paper(.plot)
        #expect(style.paper == .plot)
        #expect(style.background == .plain)

        style.sheet = .decoration(.waves)
        #expect(style.background == .waves)
        #expect(style.paper == .plain, "A decoration is drawn instead of a paper, not over it")
        #expect(style.sheet == .decoration(.waves))

        style.sheet = .paper(.dots)
        #expect(style.paper == .dots)
        #expect(style.background == .plain)
    }

    @Test("A look saved with both keeps showing its decoration")
    func legacyBoth() {
        var style = TodayStyle()
        style.paper = .plot
        style.background = .sparkles
        #expect(style.sheet == .decoration(.sparkles))
    }

    @Test("Every sheet is offered once, papers first")
    func all() {
        let all = TodaySheet.all
        #expect(Set(all).count == all.count)
        #expect(all.count == TodayPaper.allCases.count + TodayBackground.allCases.count - 1,
                "Plain paper stands for no decoration: only one of the two is offered")
        #expect(!all.contains(.decoration(.plain)))
        #expect(all.prefix(TodayPaper.allCases.count).allSatisfy { if case .paper = $0 { true } else { false } })
    }
}
