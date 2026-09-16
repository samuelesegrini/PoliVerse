import Foundation
import Testing
@testable import PoliVerse

/// A section's form: how its entries are laid out inside it, chosen like a
/// widget's size.
@Suite("Section form")
struct SectionFormTests {
    @Test("A new section lists its entries, as sections always have")
    func defaultForm() {
        #expect(TodaySection(kind: .upcoming).form == .list)
        #expect(TodaySection.Form.allCases.first == .list)
    }

    @Test("Every form has a symbol of its own")
    func labelled() {
        for form in TodaySection.Form.allCases {
            #expect(!form.systemImage.isEmpty)
        }
        #expect(Set(TodaySection.Form.allCases.map(\.rawValue)).count == TodaySection.Form.allCases.count)
    }

    @Test("Only a listing section takes a form; the current class is one row")
    func available() {
        #expect(TodaySection.Kind.upcoming.forms == TodaySection.Form.allCases)
        #expect(TodaySection.Kind.exams.forms == TodaySection.Form.allCases)
        #expect(TodaySection.Kind.currentClass.forms == [.list])
        // The timetable keeps its own course-coloured cards.
        #expect(TodaySection.Kind.timetable.forms == [.list, .rail])
    }

    @Test("A section saved before forms existed still lists its entries")
    func legacy() throws {
        let stored = Data("{\"kind\":\"upcoming\",\"density\":\"compact\",\"itemLimit\":4}".utf8)
        let section = try JSONDecoder().decode(TodaySection.self, from: stored)
        #expect(section.form == .list)
        #expect(section.density == .compact)
    }

    @Test("The form round-trips through JSON")
    func roundTrip() throws {
        var section = TodaySection(kind: .upcoming)
        section.form = .highlight
        let data = try JSONEncoder().encode(section)
        #expect(try JSONDecoder().decode(TodaySection.self, from: data).form == .highlight)
    }

    @Test("A form a kind cannot take falls back to the list")
    func unavailableFormFallsBack() {
        var style = TodayStyle()
        style.sections = [TodaySection(kind: .timetable)]
        style.updateSection(.timetable) { $0.form = .tiles }
        #expect(style.section(.timetable)?.form == .list)
        style.updateSection(.timetable) { $0.form = .rail }
        #expect(style.section(.timetable)?.form == .rail)
    }
}
