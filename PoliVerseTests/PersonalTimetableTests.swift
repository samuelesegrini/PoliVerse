import Foundation
import Testing
@testable import PoliVerse

/// The personalised timetable, read natively from the Politecnico's "orario
/// testuale" instead of showing its page.
///
/// Fixtures are fragments of the live service, 2026-09-14, built with the
/// name "Rossi Mario".
@Suite("Personal timetable")
struct PersonalTimetableTests {
    private let italian = """
    <div id="orarioTestuale">
    <div style="background-color:#f3f3ee; width: 100%; padding:2px;"><b>052496 - ALGORITHMS AND PARALLEL COMPUTING</b>
        &nbsp;(<b>Docente: </b>
                Rossi Matteo Giovanni)
    </div>
    <b>Periodo:</b> 1° semestre
        <b>Inizio lezioni: </b> 14/09/2026
        <b>Fine lezioni: </b>  23/12/2026
        <ul style="margin-top: 0px;"><li style="margin-top:5px;">Lunedì dalle 08:15 alle 10:15 in aula <a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=343&idaula=46&lang=IT">3.1.4</a> (Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 3 - Piano Primo)</li><li style="margin-top:5px;">Martedì dalle 10:15 alle 12:15 in aula <a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=343&idaula=48&lang=IT">3.1.6</a> (Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 3 - Piano Primo)</li></ul>
        <br><br>
    <div style="background-color:#f3f3ee; width: 100%; padding:2px;"><b>059156 - ANALISI MATEMATICA 1 E GEOMETRIA</b>
        &nbsp;(<b>Docente: </b>
                Notari Roberto)
    </div>
    <b>Periodo:</b> 1° semestre
        <b>Inizio lezioni: </b> 14/09/2026
        <b>Fine lezioni: </b>  23/12/2026
        <ul style="margin-top: 0px;"><li style="margin-top:5px;">Lunedì dalle 08:15 alle 10:15 in aula <a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=343&idaula=4738&lang=IT">5.02</a> (Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 5 - Piano Terra)</li><li style="margin-top:5px;">Giovedì dalle 10:15 alle 13:15 in aula <a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=343&idaula=4602&lang=IT">26.1.2</a> (Milano Città Studi - Via Golgi 20 - Edificio 26 - Piano Primo)</li></ul>
    </div>
    """

    private let english = """
    <div style="background-color:#f3f3ee; width: 100%; padding:2px;"><b>059156 - ANALISI MATEMATICA 1 E GEOMETRIA</b>
        &nbsp;(<b>Professor: </b>
                Notari Roberto)
    </div>
    <b>Period:</b> 1st semester
        <b>Start of lessons: </b> 14/09/2026
        <b>End of lesson: </b>  23/12/2026
        <ul><li style="margin-top:5px;">Wednesday from 10:15 to 13:15 in the classroom <a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=343&idaula=4738&lang=EN">5.02</a> (Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 5 - Piano Terra)</li></ul>
    """

    // MARK: Parsing

    @Test("Each teaching is read with its teacher, period and weekly slots")
    func entries() throws {
        let entries = PersonalTimetableParser.entries(italian)
        #expect(entries.map(\.code) == ["052496", "059156"])
        let first = try #require(entries.first)
        #expect(first.title == "ALGORITHMS AND PARALLEL COMPUTING")
        #expect(first.teacher == "Rossi Matteo Giovanni")
        #expect(first.semester == 1)
        #expect(first.slots.count == 2)
        let monday = first.slots[0]
        #expect(monday.weekday == 2)
        #expect(monday.startMinutes == 8 * 60 + 15)
        #expect(monday.endMinutes == 10 * 60 + 15)
        #expect(monday.room == "3.1.4")
        #expect(monday.roomID == "46")
        #expect(monday.address == "Milano Città Studi - Piazza Leonardo da Vinci 32 - Edificio 3 - Piano Primo")
        let calendar = PoliMiDate.romeCalendar
        #expect(calendar.dateComponents([.year, .month, .day], from: first.lessonsStart!) == DateComponents(year: 2026, month: 9, day: 14))
        #expect(calendar.dateComponents([.year, .month, .day], from: first.lessonsEnd!) == DateComponents(year: 2026, month: 12, day: 23))
    }

    @Test("The English page reads the same")
    func englishPage() throws {
        let entry = try #require(PersonalTimetableParser.entries(english).first)
        #expect(entry.teacher == "Notari Roberto")
        #expect(entry.semester == 1)
        #expect(entry.slots.map(\.weekday) == [4])
        #expect(entry.slots.first?.endMinutes == 13 * 60 + 15)
    }

    @Test("An empty timetable parses to nothing")
    func empty() {
        #expect(PersonalTimetableParser.entries("<div id=\"orarioTestuale\"></div>").isEmpty)
    }

    @Test("The add link on a teaching page gives the year of course and semester")
    func cartLink() throws {
        let html = """
        <TD class="ElementInfoCard2 orario_td scaglioni"><span class="cartAddVisibile"><a name="2026508M1A10591561" href="/manifesti/manifesti/controller/ManifestoPublic.do?evn_ADD_ORARIO_IN_CARRELLO=evento&aa=2026&k_corso_la=508&k_indir=M1A&semestre=1&codDescr=059156&anno_corso=1"><img src="/manifesti/images/cart/cart_put.png"></a></span></TD>
        """
        let link = try #require(PersonalTimetableParser.cartLink(in: html, code: "059156"))
        #expect(link.courseCode == "508")
        #expect(link.planCode == "M1A")
        #expect(link.semester == "1")
        #expect(link.yearOfCourse == "1")
        #expect(PersonalTimetableParser.cartLink(in: html, code: "000000") == nil)
    }

    @Test("The cart's XML reply gives the count, or the service's own error")
    func cartReply() {
        let ok = PersonalTimetableParser.cartReply("<success><num-ins-cart>2</num-ins-cart><desc-ins-add>Aggiunto al tuo orario personalizzato l'insegnamento 059156</desc-ins-add></success>")
        #expect(ok == .added(count: 2))
        let full = PersonalTimetableParser.cartReply("<error><desc-error>Hai raggiunto il numero massimo di insegnamenti</desc-error></error>")
        #expect(full == .refused("Hai raggiunto il numero massimo di insegnamenti"))
        #expect(PersonalTimetableParser.cartReply("<html>") == .refused(nil))
    }

    // MARK: Model

    private var timetable: PersonalTimetable {
        PersonalTimetable(name: "Rossi Mario", yearCode: "2026", entries: PersonalTimetableParser.entries(italian),
                          builtAt: .now)
    }

    @Test("Lessons repeat weekly between the first and last day of lessons")
    func lessons() {
        let calendar = PoliMiDate.romeCalendar
        let from = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let week = DateInterval(start: from, duration: 7 * 86400)
        let lessons = timetable.lessons(in: week)
        #expect(lessons.count == 4)
        #expect(lessons.first?.entry.code == "052496" || lessons.first?.entry.code == "059156")
        #expect(lessons.allSatisfy { calendar.component(.weekday, from: $0.start) == calendar.component(.weekday, from: $0.end) })
        let beforeStart = DateInterval(start: from.addingTimeInterval(-7 * 86400), duration: 7 * 86400)
        #expect(timetable.lessons(in: beforeStart).isEmpty)
    }

    @Test("Overlapping slots are reported as clashes")
    func clashes() {
        let clashes = timetable.clashes
        #expect(clashes.count == 1)
        #expect(Set(clashes[0].map(\.code)) == ["052496", "059156"])
    }

    @Test("A hidden teaching gives no lessons")
    func hidden() {
        var copy = timetable
        copy.hiddenCodes = ["052496"]
        let calendar = PoliMiDate.romeCalendar
        let from = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        #expect(copy.lessons(in: DateInterval(start: from, duration: 7 * 86400)).count == 2)
        #expect(copy.clashes.isEmpty)
    }

    // MARK: Hand-over to the official agenda

    private func event(_ title: String, weekday day: Int, _ hour: Int, _ minute: Int) -> AgendaEvent {
        let calendar = PoliMiDate.romeCalendar
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let date = calendar.date(byAdding: .day, value: day - 2, to: monday)!
        let start = PoliMiDate.time(hour, minute, on: date)
        return AgendaEvent(id: day * 100 + hour, title: title, start: start, end: start.addingTimeInterval(7200),
                           kind: .lecture, room: nil, roomAcronym: nil, calendarName: nil)
    }

    @Test("A teaching is confirmed once the agenda has its lessons at the same times")
    func confirmed() {
        let entry = timetable.entries[0]
        let events = [event("Algorithms and parallel computing", weekday: 2, 8, 15),
                      event("Algorithms and Parallel Computing", weekday: 3, 10, 15)]
        #expect(TimetableHandover.status(of: entry, agenda: events) == .confirmed)
        #expect(TimetableHandover.status(of: entry, agenda: [events[0]]) == .personalOnly)
    }

    @Test("A matching title at another time is not a confirmation")
    func wrongTime() {
        let entry = timetable.entries[0]
        let events = [event("Algorithms and parallel computing", weekday: 2, 14, 0),
                      event("Algorithms and parallel computing", weekday: 5, 16, 0)]
        #expect(TimetableHandover.status(of: entry, agenda: events) == .personalOnly)
    }

    @Test("Retiring is suggested once most teachings are in the agenda")
    func suggestRetire() {
        #expect(TimetableHandover.suggestsRetiring(confirmed: 4, of: 5))
        #expect(!TimetableHandover.suggestsRetiring(confirmed: 3, of: 5))
        #expect(!TimetableHandover.suggestsRetiring(confirmed: 0, of: 0))
    }
}

@Suite("Personal timetable calendar export")
struct PersonalTimetableExportTests {
    private let calendar = PoliMiDate.romeCalendar

    @Test("Each slot becomes one weekly event from its first lesson to the last day of lessons")
    func drafts() throws {
        // 14/09/2026 is a Monday; a Wednesday slot starts on the 16th.
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 12, day: 23))!
        let entry = PersonalTimetable.Entry(
            code: "052496", title: "ALGORITHMS", teacher: "Rossi", semester: 1, lessonsStart: start, lessonsEnd: end,
            slots: [.init(weekday: 4, startMinutes: 615, endMinutes: 735, room: "3.1.1", roomID: "63", address: "Edificio 3")])
        let timetable = PersonalTimetable(name: "Rossi Mario", yearCode: "2026", entries: [entry], builtAt: .now)
        let drafts = CalendarExport.drafts(for: timetable)
        let draft = try #require(drafts.first)
        #expect(drafts.count == 1)
        #expect(calendar.dateComponents([.month, .day, .hour, .minute], from: draft.start)
            == DateComponents(month: 9, day: 16, hour: 10, minute: 15))
        #expect(draft.end.timeIntervalSince(draft.start) == 7200)
        #expect(draft.repeatsUntil == calendar.date(byAdding: .day, value: 1, to: end))
        #expect(draft.location == "Aula 3.1.1, Edificio 3")
    }

    @Test("Hidden teachings and slots without dates are not exported")
    func skipped() {
        let entry = PersonalTimetable.Entry(code: "1", title: "X", teacher: nil, semester: 1, lessonsStart: nil,
                                            lessonsEnd: nil, slots: [.init(weekday: 2, startMinutes: 0, endMinutes: 60, room: nil, roomID: nil, address: nil)])
        var timetable = PersonalTimetable(name: "A", yearCode: "2026", entries: [entry], builtAt: .now)
        #expect(CalendarExport.drafts(for: timetable).isEmpty)
        timetable.hiddenCodes = ["1"]
        #expect(CalendarExport.drafts(for: timetable).isEmpty)
    }
}

@Suite("Personal timetable refresh")
struct PersonalTimetableRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func timetable(builtDaysAgo days: Double, lessonsEndInDays end: Double = 30) -> PersonalTimetable {
        let entry = PersonalTimetable.Entry(code: "1", title: "X", teacher: nil, semester: 1, lessonsStart: nil,
                                            lessonsEnd: now.addingTimeInterval(end * 86400), slots: [])
        var value = PersonalTimetable(name: "A", yearCode: "2026", entries: [entry], builtAt: now.addingTimeInterval(-days * 86400))
        value.sources = [PersonalTimetable.Source(ManifestoTeaching(
            code: "1", name: "X", courseCode: "1", planCode: nil, idItemOfferta: nil, idRiga: nil,
            semester: "1", year: "2026", credits: nil, school: nil, degreeCourse: nil))]
        return value
    }

    @Test("Rebuilt after a week, while lessons still run")
    func stale() {
        #expect(PersonalTimetableModel.needsRefresh(timetable(builtDaysAgo: 8), now: now))
        #expect(!PersonalTimetableModel.needsRefresh(timetable(builtDaysAgo: 2), now: now))
    }

    @Test("Not rebuilt once retired, or once every teaching's lessons have ended")
    func notNeeded() {
        var retired = timetable(builtDaysAgo: 8)
        retired.retiredAt = now
        #expect(!PersonalTimetableModel.needsRefresh(retired, now: now))
        #expect(!PersonalTimetableModel.needsRefresh(timetable(builtDaysAgo: 8, lessonsEndInDays: -1), now: now))
    }
}

@Suite("Personal timetable choices")
struct PersonalTimetableChoiceTests {
    /// Modelled on the page's own script — `show_sezioni` reads
    /// `input[name=sel_sezione]` valued "<semestre>_<sezione>" — since no
    /// teaching offered sections when the fixtures were taken.
    private let sections = """
    <form><input type="hidden" name="c_insegn_sel_sezione" value="088715"/>
    <input type="hidden" name="ac_sel_sezione" value="3"/>
    <table><tr><td><input type="radio" name="sel_sezione" value="1_A" checked="checked"/></td><td>Sezione A - Rossi Mario</td></tr>
    <tr><td><input type="radio" name="sel_sezione" value="1_B"/></td><td> Sezione B -  Bianchi Anna </td></tr></table></form>
    """

    @Test("A teaching page with sections links the dialog, with its keys")
    func sectionsLink() throws {
        let html = """
        <td class="ElementInfoCard2 orario_td con_sezioni"><a name="k1" href="/manifesti/manifesti/controller/ManifestoPublic.do?evn_x=evento&aa=2026&k_corso_la=346&k_indir=M1A&codDescr=088715&anno_corso=3&idItemOfferta=1&idGruppo=2&idRiga=3"><img src="put.png"></a></td>
        """
        let link = try #require(PersonalTimetableParser.sectionsLink(in: html, code: "088715"))
        #expect(link.courseCode == "346")
        #expect(link.yearOfCourse == "3")
        #expect(link.idGruppo == "2")
        #expect(PersonalTimetableParser.sectionsLink(in: html, code: "000000") == nil)
    }

    @Test("The sections dialog lists each option with its semester and the preselected one")
    func sectionOptions() {
        let options = PersonalTimetableParser.sections(sections)
        #expect(options.map(\.name) == ["A", "B"])
        #expect(options.map(\.semester) == ["1", "1"])
        #expect(options.map(\.label) == ["Sezione A - Rossi Mario", "Sezione B - Bianchi Anna"])
        #expect(options.map(\.isPreselected) == [true, false])
    }

    @Test("A catalogue row belongs to the student's degree course when the names agree")
    func degree() {
        #expect(DegreeCourseMatch.matches("(1 liv.)(ord. 270) - BV (352) Ingegneria Energetica", plan: "INGEGNERIA ENERGETICA"))
        #expect(!DegreeCourseMatch.matches("(1 liv.)(ord. 270) - MI (358) Ingegneria Informatica", plan: "Ingegneria Energetica"))
        #expect(!DegreeCourseMatch.matches(nil, plan: "Ingegneria Energetica"))
    }
}
