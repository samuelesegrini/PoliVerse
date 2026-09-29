import Foundation
import Testing
@testable import PoliVerse

/// The personal timetable's builder state: what is picked, what is kept after
/// a delete, and when a built timetable asks to be rebuilt.
///
/// Every model here starts from a preview, so none reads the timetable saved
/// on the simulator.
@Suite("Personal timetable model")
@MainActor
struct PersonalTimetableModelTests {
    private static let now = PoliMiDate.romeCalendar.date(
        from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!

    private static func teaching(_ code: String) -> ManifestoTeaching {
        ManifestoTeaching(code: code, name: "Insegnamento \(code)", courseCode: "1234", planCode: "PL",
                          idItemOfferta: "IO", idRiga: "IR", semester: "1", year: "2026",
                          credits: 10, school: nil, degreeCourse: nil)
    }

    private static func timetable(builtDaysAgo days: Double, lessonsEnd: Date?, retired: Bool = false,
                                  sources: Bool = true) -> PersonalTimetable {
        var built = PersonalTimetable(
            name: "Rossi Mario", yearCode: "2026",
            entries: [.init(code: "086457", title: "Analisi", teacher: nil, semester: 1,
                            lessonsStart: nil, lessonsEnd: lessonsEnd, slots: [])],
            builtAt: now.addingTimeInterval(-days * 86_400))
        if sources { built.sources = [.init(teaching("086457"))] }
        if retired { built.retiredAt = now }
        return built
    }

    private func model(_ preview: PersonalTimetable? = nil) -> PersonalTimetableModel {
        PersonalTimetableModel(cart: TimetableCart(pages: FixturePages()),
                               preview: preview ?? Self.timetable(builtDaysAgo: 0, lessonsEnd: nil))
    }

    // MARK: - Picking

    @Test("Picking stops at the cart's capacity, and a second tap unpicks")
    func capacity() {
        let personal = model()
        let start = personal.selection.count
        for index in 0..<(PersonalTimetableModel.capacity + 3) {
            personal.toggle(Self.teaching("T\(index)"))
        }
        #expect(personal.selection.count == PersonalTimetableModel.capacity)

        let first = personal.selection[start]
        personal.toggle(first)
        #expect(!personal.isSelected(first))
        #expect(personal.selection.count == PersonalTimetableModel.capacity - 1)
    }

    @Test("A timetable opens with its teachings already picked")
    func previewSeedsSelection() {
        #expect(model().selection.map(\.code) == ["086457"])
    }

    // MARK: - Deleting

    /// A section kept from the deleted timetable used to be applied to the
    /// next build without the question being asked again.
    @Test("Deleting forgets the sections chosen for it")
    func deleteForgetsSections() {
        let personal = model()
        let teaching = Self.teaching("086457")
        let link = PersonalTimetableParser.SectionsLink(
            courseCode: "1234", planCode: "PL", yearOfCourse: "1",
            idItemOfferta: "IO", idGruppo: "G", idRiga: "IR")
        personal.choose(.init(semester: "1", name: "A-L", label: "A-L", isPreselected: false),
                        for: teaching, link: link)
        #expect(!personal.sectionChoices.isEmpty)

        personal.delete()

        #expect(personal.timetable == nil)
        #expect(personal.selection.isEmpty)
        #expect(personal.sectionChoices.isEmpty)
        #expect(personal.sectionQuestions.isEmpty)
        #expect(personal.refused.isEmpty)
    }

    // MARK: - Refreshing

    struct RefreshCase: Sendable, CustomTestStringConvertible {
        let label: String
        let builtDaysAgo: Double
        let lessonsEndInDays: Double?
        var retired = false
        var sources = true
        let expected: Bool
        var testDescription: String { label }
    }

    /// A week old and still with lessons to come: the Politecnico moves rooms
    /// and hours during term. Anything else would only cost requests.
    @Test("A timetable asks to be rebuilt only when it is stale and still in use", arguments: [
        RefreshCase(label: "a week old, lessons ahead", builtDaysAgo: 7, lessonsEndInDays: 30, expected: true),
        RefreshCase(label: "six days old", builtDaysAgo: 6, lessonsEndInDays: 30, expected: false),
        RefreshCase(label: "lessons over", builtDaysAgo: 30, lessonsEndInDays: -1, expected: false),
        RefreshCase(label: "no end date known", builtDaysAgo: 30, lessonsEndInDays: nil, expected: true),
        RefreshCase(label: "retired", builtDaysAgo: 30, lessonsEndInDays: 30, retired: true, expected: false),
        RefreshCase(label: "built before sources were kept", builtDaysAgo: 30, lessonsEndInDays: 30,
                    sources: false, expected: false),
    ])
    func needsRefresh(_ refresh: RefreshCase) {
        let timetable = Self.timetable(
            builtDaysAgo: refresh.builtDaysAgo,
            lessonsEnd: refresh.lessonsEndInDays.map { Self.now.addingTimeInterval($0 * 86_400) },
            retired: refresh.retired, sources: refresh.sources)
        #expect(PersonalTimetableModel.needsRefresh(timetable, now: Self.now) == refresh.expected)
    }
}
