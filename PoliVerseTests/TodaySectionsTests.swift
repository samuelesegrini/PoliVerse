import Foundation
import Testing
@testable import PoliVerse

/// The page's sections: an ordered list the student arranges in Personalizza.
@Suite("Today sections")
struct TodaySectionsTests {
    private func kinds(_ style: TodayStyle) -> [TodaySection.Kind] { style.visibleSections.map(\.kind) }

    @Test("A new look shows In arrivo, then the timetable")
    func defaults() {
        #expect(kinds(TodayStyle()) == [.upcoming, .timetable])
    }

    @Test("Adding appends a section once; a kind already on the page is not added again")
    func add() {
        var style = TodayStyle()
        style.addSection(.deadlines)
        style.addSection(.upcoming)
        #expect(kinds(style) == [.upcoming, .timetable, .deadlines])
        #expect(style.addableSections == [.currentClass, .exams])
    }

    @Test("Hiding takes the section off the page and offers it again, keeping its settings and place")
    func hide() {
        var style = TodayStyle()
        style.updateSection(.upcoming) { $0.card = .glass; $0.itemLimit = 5 }
        style.hideSection(.upcoming)
        #expect(kinds(style) == [.timetable])
        #expect(style.addableSections.first == .upcoming)
        style.addSection(.upcoming)
        #expect(kinds(style) == [.upcoming, .timetable])
        #expect(style.section(.upcoming)?.card == .glass)
        #expect(style.section(.upcoming)?.itemLimit == 5)
    }

    @Test("Moving up and down steps over hidden sections, and stops at the ends")
    func step() {
        var style = TodayStyle()
        style.addSection(.exams)
        style.hideSection(.timetable)
        style.moveSection(.exams, by: -1)
        #expect(kinds(style) == [.exams, .upcoming])
        style.moveSection(.exams, by: -1)
        #expect(kinds(style) == [.exams, .upcoming])
        style.moveSection(.exams, by: 1)
        #expect(kinds(style) == [.upcoming, .exams])
    }

    @Test("The timetable shows the whole day; only the lists that can run long take a number")
    func limits() {
        #expect(!TodaySection.Kind.timetable.listsItems)
        #expect(!TodaySection.Kind.currentClass.listsItems)
        #expect(TodaySection.Kind.upcoming.listsItems && TodaySection.Kind.exams.listsItems)
    }

    @Test("Dropping a section on another puts it in that one's place")
    func move() {
        var style = TodayStyle()
        style.addSection(.exams)
        style.moveSection(.exams, onto: .upcoming)
        #expect(kinds(style) == [.exams, .upcoming, .timetable])
        style.moveSection(.exams, onto: .timetable)
        #expect(kinds(style) == [.upcoming, .timetable, .exams])
        style.moveSection(.exams, onto: .exams)
        #expect(kinds(style) == [.upcoming, .timetable, .exams])
    }

    @Test("A section's settings change in place and the item count stays in range")
    func update() {
        var style = TodayStyle()
        style.updateSection(.upcoming) {
            $0.card = .glass
            $0.density = .compact
            $0.itemLimit = 40
        }
        let upcoming = try? #require(style.section(.upcoming))
        #expect(upcoming?.card == .glass)
        #expect(upcoming?.density == .compact)
        #expect(upcoming?.itemLimit == TodaySection.itemLimits.upperBound)
    }

    @Test("Sections round-trip through the stored string, settings included")
    func roundTrip() throws {
        var style = TodayStyle()
        style.addSection(.currentClass)
        style.moveSection(.currentClass, onto: .upcoming)
        style.updateSection(.timetable) { $0.tinted = true; $0.card = .plain }
        style.hideSection(.upcoming)
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.sections == style.sections)
    }

    @Test("A look saved before sections existed keeps what it showed")
    func legacy() throws {
        let hidden = try #require(TodayStyle(rawValue: #"{"showsUpcoming":false,"showsTimetable":true}"#))
        #expect(kinds(hidden) == [.timetable])
        #expect(hidden.addableSections.first == .upcoming)
        let old = try #require(TodayStyle(rawValue: #"{"dateFont":"serif"}"#))
        #expect(kinds(old) == [.upcoming, .timetable])
    }

    @Test("A stored section of a kind this version does not know is skipped, not the whole look")
    func unknownKind() throws {
        let style = try #require(TodayStyle(rawValue: #"{"sections":[{"kind":"weather"},{"kind":"exams","itemLimit":2}]}"#))
        #expect(kinds(style) == [.exams])
        #expect(style.section(.exams)?.itemLimit == 2)
    }
}
