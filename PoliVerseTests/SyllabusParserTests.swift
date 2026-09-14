import Foundation
import Testing
@testable import PoliVerse

/// The scheda insegnamento, read field by field.
///
/// Every fragment here is from the live pages (`SchedaPublic.do`, 2026/2027):
/// c_classe 888914 (097683 Machine Learning, taught in English) and 889303
/// (Metodi analitici e numerici, taught in Italian), with the page's
/// whitespace squeezed. A scraper tested against invented markup tests only
/// the invention (docs/manifesti.md).
@Suite("Syllabus parser")
struct SyllabusParserTests {
    private let summary = """
    <td class="TitleInfoCard">Scheda Riassuntiva</td></TR></TABLE><TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard1 jaf-card-element">Anno Accademico</td><td colspan="3" class="ElementInfoCard2 jaf-card-element">2026/2027</td></tr>
    <tr><td class="ElementInfoCard1 jaf-card-element">Cfu</td><td class="ElementInfoCard2 jaf-card-element">5.00</td><td class="ElementInfoCard1 jaf-card-element">Tipo insegnamento</td><td class="ElementInfoCard2 jaf-card-element">Monodisciplinare</td></tr>
    <tr><td class="ElementInfoCard1 jaf-card-element">Docenti: Titolare (Co-titolari)</td><td colspan="3" class="ElementInfoCard2 jaf-card-element"><a target="_blank"href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=167&evn_didattica=evento&k_doc=138695">Restelli Marcello</a>, <a target="_blank"href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=167&evn_didattica=evento&k_doc=92132">Loiacono Daniele</a></td></tr>
    </TABLE>
    <TABLE width="100%" class="TableDati" cellpadding="5" cellspacing="0"> <TBODY><TR><TH width="30%" class="HeadColumn1" style="text-align:left">Corso di Studi</TH><TH class="HeadColumn1">Codice Piano di Studio preventivamente approvato</TH><TH class="HeadColumn1">Da (compreso)</TH><TH class="HeadColumn1">A (escluso)</TH><TH class="HeadColumn1">Insegnamento</TH></TR>
    <TR><TD class="ElementInfoCard2">Ing Ind - Inf (Mag.)(ord. 96/23) - MI (1077) BIOMEDICAL ENGINEERING</TD><TD class="ElementInfoCard2">*</TD><TD class="ElementInfoCard2">P</TD><TD class="ElementInfoCard2">ZZZZ</TD><TD class="ElementInfoCard2">097683 - MACHINE LEARNING</TD></TR>
    <TR><TD class="ElementInfoCard2">Ing Ind - Inf (Mag.)(ord. 96/23) - MI (542) COMPUTER SCIENCE AND ENGINEERING</TD><TD class="ElementInfoCard2">*</TD><TD class="ElementInfoCard2">A</TD><TD class="ElementInfoCard2">P</TD><TD class="ElementInfoCard2">097683 - MACHINE LEARNING</TD></TR>
    </TBODY></TABLE>
    """

    private let assessment = """
    <td class="TitleInfoCard">Modalità di valutazione</td></TR></TABLE><TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard2 jaf-card-element"><ul><li>Prova scritta obbligatoria, senza prove in itinere</li><li>Prova orale condizionata (a scelta del docente)</li></ul></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><p>The assessment will be based on a written exam at the end of the course, where both theoretical competence and modeling skills will be tested.&nbsp;</p></td></tr>
    </TABLE>
    """

    private let bibliography = """
    <td class="TitleInfoCard">Bibliografia</td></TR></TABLE><TABLE class="BoxInfoCard"><tr><td class="ElementInfoCard2 jaf-card-element">
    <span style="float:left; width:2em"><img title="Risorsa bibliografica obbligatoria" alt="Risorsa bibliografica obbligatoria" src="/schedaincarico/images/bibliografia/book_blue.png" border="0"></span><i>Christopher M. Bishop</i>, <b>Pattern Recognition and Machine Learning</b>, Editore: Springer-Verlag Berlin, Heidelberg, Anno edizione: 2006, ISBN: 0387310738 <a href="https://www.microsoft.com/en-us/research/people/cmbishop/prml-book/" target="_blank">https://www.microsoft.com/en-us/research/people/cmbishop/prml-book/</a>
    <div style="height:1em; border-top:1px dashed #CCCCCC; margin-top:1em;"></div>
    <span style="float:left; width:2em"><img title="Risorsa bibliografica facoltativa" alt="Risorsa bibliografica facoltativa" src="/schedaincarico/images/bibliografia/book_brown.png" border="0"></span><i>Murphy, K. P.</i>, <b>Probabilistic Machine Learning: An introduction</b>, Editore: MIT Press, Anno edizione: 2022 <a href="https://probml.github.io/pml-book/book1.html" target="_blank">https://probml.github.io/pml-book/book1.html</a>
    <div style="height:1em; border-top:1px dashed #CCCCCC; margin-top:1em;"></div>
    </td></tr></TABLE>
    """

    private let software = """
    <td class="TitleInfoCard">Software utilizzato</td></TR></TABLE><TABLE class="BoxInfoCard"><tr><td class="ElementInfoCard2 jaf-card-element">Nessun software richiesto</td></tr></TABLE>
    <style>.lineTop { border-top: 2px solid #bbbbbb; }</style>
    """

    private let forms = """
    <td class="TitleInfoCard">Forme didattiche</td></TR></TABLE><TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard1">Forma Didattica</td><td class="ElementInfoCard1">Ore Didattica Assistita (hh:mm)</td><td class="ElementInfoCard1">% Didattica Assistita</td></tr>
    <tr><td class="ElementInfoCard2">DIDATTICA TRASMISSIVA/FRONTALE</td><td class="ElementInfoCard2 alignCenter">30:00</td><td class="ElementInfoCard2 alignCenter">60.0 %</td></tr>
    <tr><td class="ElementInfoCard2">DIDATTICA INTERATTIVA/PARTECIPATIVA</td><td class="ElementInfoCard2 alignCenter">0:00</td><td class="ElementInfoCard2 alignCenter">0.0 %</td></tr>
    <tr><td class="ElementInfoCard2">DIDATTICA LABORATORIALE</td><td class="ElementInfoCard2 alignCenter">20:00</td><td class="ElementInfoCard2 alignCenter">40.0 %</td></tr>
    <tr><td class="ElementInfoCard1 lineTop">Totale ore didattica assistita (hh:mm)</td><td class="ElementInfoCard2 alignCenter lineTop">50:00</td></tr>
    <tr><td class="ElementInfoCard1">Totale ore di studio autonomo (hh:mm)</td><td class="ElementInfoCard2 alignCenter">75:00</td></tr>
    </TABLE>
    """

    private let englishTaught = """
    <td class="TitleInfoCard">Informazioni in lingua inglese a supporto dell'internazionalizzazione</td></TR></TABLE><TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align: left">Insegnamento erogato in lingua <img align="absbottom" border="none" width="16px" src="/schedaincarico/images/bandiera_inglese.png"> Inglese</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Disponibilità di materiale didattico/slides in lingua inglese</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Disponibilità di libri di testo/bibliografia in lingua inglese</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Possibilità di sostenere l'esame in lingua inglese</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Disponibilità di supporto didattico in lingua inglese</div></td></tr>
    </TABLE>
    """

    private let italianTaught = """
    <td class="TitleInfoCard">Informazioni in lingua inglese a supporto dell'internazionalizzazione</td></TR></TABLE><TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align: left">Insegnamento erogato in lingua <img align="absbottom" border="none" width="16px" src="/schedaincarico/images/bandiera_italiana.png"> Italiano</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Disponibilità di libri di testo/bibliografia in lingua inglese</div></td></tr>
    <tr><td class="ElementInfoCard2 jaf-card-element"><div style="text-align:left">Possibilità di sostenere l'esame in lingua inglese</div></td></tr>
    </TABLE>
    """

    private let objectives = """
    <td class="TitleInfoCard">Obiettivi dell'insegnamento</td></TR></TABLE><TABLE class="BoxInfoCard"><tr><td class="ElementInfoCard2 jaf-card-element"><p>This course provides an introduction to Machine Learning.</p></td></tr></TABLE>
    <td class="TitleInfoCard">Prerequisiti</td></TR></TABLE><TABLE class="BoxInfoCard"><tr><td class="ElementInfoCard2 jaf-card-element">Students are required to know the basics of statistics, linear algebra, calculus, and optimization theory.</td></tr></TABLE>
    """

    private var page: String { summary + objectives + assessment + bibliography + software + forms + englishTaught }

    @Test("Sections come from the page's own titles, without the style sheet")
    func sections() {
        let syllabus = ManifestoParser.syllabus(page)
        #expect(syllabus.objectives == "This course provides an introduction to Machine Learning.")
        #expect(syllabus.sections.map(\.title).contains("Prerequisiti"))
        #expect(!syllabus.sections.contains { $0.body.contains("lineTop") })
        // Shown in their own form, so not repeated as prose.
        #expect(!syllabus.sections.contains { $0.title == "Scheda Riassuntiva" || $0.title == "Bibliografia" })
    }

    @Test("The teachers, credits and type are read from the summary card")
    func summaryCard() {
        let syllabus = ManifestoParser.syllabus(page)
        #expect(syllabus.teachers.map(\.name) == ["Restelli Marcello", "Loiacono Daniele"])
        #expect(syllabus.teachers.first?.kDoc == "138695")
        #expect(syllabus.credits == 5)
        #expect(syllabus.teachingType == "Monodisciplinare")
    }

    /// The same teaching serves several degree courses, each with its own
    /// bracket.
    @Test("The bracket of each degree course is read")
    func brackets() {
        let brackets = ManifestoParser.syllabus(page).brackets
        #expect(brackets.count == 2)
        #expect(brackets[1].degreeCourse.contains("COMPUTER SCIENCE AND ENGINEERING"))
        #expect(brackets[1].from == "A")
        #expect(brackets[1].to == "P")
    }

    @Test("How the exam works is read as its own list")
    func assessmentList() {
        let syllabus = ManifestoParser.syllabus(page)
        #expect(syllabus.assessment == ["Prova scritta obbligatoria, senza prove in itinere",
                                        "Prova orale condizionata (a scelta del docente)"])
        #expect(syllabus.assessmentNotes?.hasPrefix("The assessment will be based") == true)
    }

    @Test("Each book has its authors, title, details, link and whether it is required")
    func books() {
        let books = ManifestoParser.syllabus(page).books
        #expect(books.count == 2)
        #expect(books[0].authors == "Christopher M. Bishop")
        #expect(books[0].title == "Pattern Recognition and Machine Learning")
        #expect(books[0].isRequired)
        #expect(books[0].details?.contains("Springer") == true)
        #expect(books[0].url?.host() == "www.microsoft.com")
        #expect(!books[1].isRequired)
    }

    @Test("Software and teaching hours are read")
    func workload() {
        let syllabus = ManifestoParser.syllabus(page)
        #expect(syllabus.software == "Nessun software richiesto")
        #expect(syllabus.teachingForms.map(\.minutes) == [30 * 60, 20 * 60])   // zero rows dropped
        #expect(syllabus.teachingForms.first?.name == "DIDATTICA TRASMISSIVA/FRONTALE")
        #expect(syllabus.assistedMinutes == 50 * 60)
        #expect(syllabus.selfStudyMinutes == 75 * 60)
    }

    /// Only what applies is listed: an Italian-taught course with English
    /// books and an English exam option lists just those two.
    @Test("The language and the English support offered are read")
    func language() {
        let english = ManifestoParser.syllabus(page)
        #expect(english.language == .english)
        #expect(english.englishSupport == [.slides, .books, .exam, .tutoring])
        let italian = ManifestoParser.syllabus(italianTaught)
        #expect(italian.language == .italian)
        #expect(italian.englishSupport == [.books, .exam])
    }

    // MARK: - Detail page

    /// 2024 reform codes: `IINF-05/A`, not `ING-INF/05`.
    @Test("Scientific sectors in the new format are read")
    func newSSD() {
        let row = """
        <TR><TD class="ElementInfoCard2">B</TD><TD class="ElementInfoCard2">IINF-05/A</TD><TD class="ElementInfoCard2">SISTEMI DI ELABORAZIONE DELLE INFORMAZIONI</TD><TD class="ElementInfoCard2">5.0</TD></TR>
        """
        let ssd = ManifestoParser.ssd(row)
        #expect(ssd.first?.code == "IINF-05/A")
        #expect(ssd.first?.credits == 5)
        #expect(ManifestoParser.ssd(row.replacingOccurrences(of: "IINF-05/A", with: "ING-INF/05")).first?.code == "ING-INF/05")
    }

    /// A single-module teaching has no code column: its one row is the
    /// teaching itself, and it is where the teacher, the language and the
    /// syllabus link are.
    @Test("A single-module row without a code is still a module")
    func singleModule() {
        let row = """
        <TR><TD id=""width="3%" class="ElementInfoCard2 orario_td scaglioni" style="text-align:center">---</TD><TD id=""width="10%" class="ElementInfoCard2" style="text-align:center">A</TD><TD id=""width="10%" class="ElementInfoCard2" style="text-align:center">ZZZZ</TD><TD width="25%" class="ElementInfoCard2" style="text-align:left"><a href="/manifesti/manifesti/controller/ricerche/RicercaPerDocentiPublic.do?evn_didattica=evento&k_doc=138695&aa=2026&lang=IT&jaf_currentWFID=main">Restelli Marcello</a></TD><TD width="5%" class="ElementInfoCard2" style="text-align:center"><img src="/manifesti/images/flags/en.png" border="none" height="16px"></TD><TD colspan="2" class="ElementInfoCard2" style="text-align:center"><a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=178&c_classe=888914"><img src="/manifesti/images/scheda.gif" border="none" ></a></TD></TR>
        """
        let modules = ManifestoParser.modules(row, teachingCode: "097683", teachingName: "MACHINE LEARNING")
        #expect(modules.count == 1)
        #expect(modules.first?.code == "097683")
        #expect(modules.first?.teachers.first?.name == "Restelli Marcello")
        #expect(modules.first?.language == .english)
        #expect(modules.first?.syllabusID == "888914")
        #expect(modules.first?.scaglioneFrom == "A")
    }

    /// 889303: the service's list, then the teacher's own list in the notes.
    @Test("Only the service's list is the exam format; the teacher's lists stay in the notes")
    func teacherLists() {
        let html = """
        <td class="TitleInfoCard">Modalità di valutazione</td></TR></TABLE><TABLE class="BoxInfoCard">
        <tr><td class="ElementInfoCard2 jaf-card-element"><ul>
        <li>Prova scritta obbligatoria, senza prove in itinere</li>
        <li>Prova orale condizionata (a scelta del docente)</li>
        </ul></td></tr>
        <tr><td class="ElementInfoCard2 jaf-card-element"><p>La prova scritta verifica la capacità:</p><ul><li>di rispondere a quesiti di natura teorica sugli argomenti trattati durante l'insegnamento</li></ul></td></tr>
        </TABLE>
        """
        let syllabus = ManifestoParser.syllabus(html)
        #expect(syllabus.assessment.count == 2)
        #expect(syllabus.assessmentNotes?.contains("La prova scritta verifica") == true)
        #expect(syllabus.assessmentNotes?.contains("Prova orale condizionata") == false)
        // The teacher's own list is kept with the notes.
        #expect(syllabus.assessmentNotes?.contains("di rispondere a quesiti") == true)
    }
}

/// Which scheda is the student's, among the rows a teaching code returns.
@Suite("Syllabus picker")
struct SyllabusPickerTests {
    private func module(_ from: String?, _ to: String?, syllabus: String?) -> ManifestoModule {
        ManifestoModule(code: "097683", name: "MACHINE LEARNING", teachers: [], credits: nil, period: nil,
                        language: nil, scaglioneFrom: from, scaglioneTo: to, syllabusID: syllabus)
    }

    private func detail(degree: String, modules: [ManifestoModule]) -> ManifestoDetail {
        ManifestoDetail(code: "097683", name: "MACHINE LEARNING",
                        context: [(label: "Corso di Studi", value: degree)],
                        facts: [], summary: nil, ssd: [], modules: modules, languages: [])
    }

    private var details: [ManifestoDetail] {
        [detail(degree: "(Mag.)(ord. 96/23) - MI (511) Geoinformatics Engineering",
                modules: [module("A", "ZZZZ", syllabus: "888914")]),
         detail(degree: "(Mag.)(ord. 96/23) - MI (542) Computer Science and Engineering",
                modules: [module("A", "P", syllabus: "888914"), module("P", "ZZZZ", syllabus: "888915")])]
    }

    @Test("The student's degree course and surname bracket decide the scheda")
    func degreeAndSurname() {
        let picked = SyllabusPicker.pick(details, surname: "Rossi",
                                         degreeName: "COMPUTER SCIENCE AND ENGINEERING")
        #expect(picked?.module.syllabusID == "888915")
        #expect(picked?.matchesDegree == true)
        let early = SyllabusPicker.pick(details, surname: "Bianchi",
                                        degreeName: "Computer Science and Engineering")
        #expect(early?.module.syllabusID == "888914")
    }

    @Test("Without a degree, the first row with a scheda; without a surname, the first module")
    func fallbacks() {
        let unknown = SyllabusPicker.pick(details, surname: nil, degreeName: "Ingegneria Gestionale")
        #expect(unknown?.module.syllabusID == "888914")
        #expect(unknown?.matchesDegree == false)
        #expect(SyllabusPicker.pick([detail(degree: "X", modules: [module(nil, nil, syllabus: nil)])],
                                    surname: "Rossi", degreeName: nil) == nil)
    }

    private func row(_ course: String, degree: String?) -> ManifestoTeaching {
        ManifestoTeaching(code: "097683", name: "MACHINE LEARNING", courseCode: course, planCode: nil,
                          idItemOfferta: nil, idRiga: nil, semester: nil, year: nil, credits: nil, school: nil,
                          degreeCourse: degree)
    }

    @Test("The student's degree course is read first, keeping the service's order otherwise")
    func ordering() {
        let rows = [row("511", degree: "(Mag.) - MI (511) Geoinformatics Engineering"),
                    row("542", degree: "(Mag.) - MI (542) Computer Science and Engineering"),
                    row("600", degree: nil)]
        #expect(SyllabusPicker.ordered(rows, degreeName: "Computer Science and Engineering").map(\.courseCode)
            == ["542", "511", "600"])
        #expect(SyllabusPicker.ordered(rows, degreeName: nil).map(\.courseCode) == ["511", "542", "600"])
    }

    @Test("A pick survives the disk cache")
    func pickRoundTrip() throws {
        let picked = try #require(SyllabusPicker.pick(details, surname: "Rossi", degreeName: "Computer Science and Engineering"))
        let decoded = try JSONDecoder().decode(SyllabusPicker.Pick.self, from: JSONEncoder().encode(picked))
        #expect(decoded == picked)
    }

    @Test("A syllabus survives the disk cache")
    func syllabusRoundTrip() throws {
        var syllabus = Syllabus(sections: [(title: "Obiettivi", body: "Imparare")])
        syllabus.assessment = ["Prova scritta obbligatoria"]
        syllabus.books = [SyllabusBook(authors: "Bishop", title: "PRML", details: nil, url: nil, isRequired: true)]
        syllabus.englishSupport = [.slides]
        syllabus.teachers = [ManifestoTeacher(name: "Rossi", kDoc: "1")]
        let decoded = try JSONDecoder().decode(Syllabus.self, from: JSONEncoder().encode(syllabus))
        #expect(decoded == syllabus)
        #expect(decoded.objectives == "Imparare")
    }
}
