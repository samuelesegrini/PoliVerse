import Foundation
import Testing
@testable import PoliVerse

/// Parsing the Manifesti degli Studi.
///
/// The fixtures are real fragments taken from the live service on
/// 2026-09-12 — a scraper tested against invented markup tests nothing but
/// the invention.
@Suite("Manifesto parser")
struct ManifestoParserTests {
    /// The card structure every field on the teaching page uses.
    private let contextCard = """
    <td class="TitleInfoCard">Contesto</td></TR></TABLE>
    <TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard1 jaf-card-element"> Anno Accademico </td>
        <td class="ElementInfoCard2 jaf-card-element"> 2026/2027 </td></tr>
    <tr><td class="ElementInfoCard1 jaf-card-element"> Scuola </td>
        <td class="ElementInfoCard2 jaf-card-element"> Scuola di Ingegneria Industriale e dell'Informazione </td></tr>
    <tr><td class="ElementInfoCard1 jaf-card-element"> Corso di Studi </td>
        <td class="ElementInfoCard2 jaf-card-element"> (1 liv.)(ord. 270) - BV (352) Ingegneria Energetica </td></tr>
    </TABLE>
    <td class="TitleInfoCard">Scheda Insegnamento</td></TR></TABLE>
    <TABLE class="BoxInfoCard">
    <tr><td class="ElementInfoCard1"> Codice Identificativo </td>
        <td class="ElementInfoCard2"> 086214 </td></tr>
    <tr><td class="ElementInfoCard1"> Denominazione Insegnamento </td>
        <td class="ElementInfoCard2"> METODI ANALITICI E NUMERICI PER L'INGEGNERIA </td></tr>
    <tr><td class="ElementInfoCard1"> Crediti Formativi Universitari (CFU) </td>
        <td class="ElementInfoCard2"> 10.0 </td></tr>
    <tr><td class="ElementInfoCard1"> Programma sintetico </td>
        <td class="ElementInfoCard2"> Scopo di questo corso &egrave; introdurre gli strumenti matematici. </td></tr>
    </TABLE>
    """

    @Test("A labelled value is read from its card")
    func cardValue() {
        #expect(HTMLScraper.cardValue("Anno Accademico", in: contextCard) == "2026/2027")
        #expect(HTMLScraper.cardValue("Codice Identificativo", in: contextCard) == "086214")
    }

    /// Entities are decoded on the way out — the service emits `&egrave;`
    /// rather than the character, everywhere.
    @Test("Entities in a card value are decoded")
    func entities() {
        let detail = ManifestoParser.detail(contextCard, code: "086214")
        #expect(detail?.summary?.contains("è introdurre") == true)
        #expect(detail?.summary?.contains("&egrave;") == false)
    }

    @Test("Sections are separated by their titles")
    func sections() {
        let contesto = HTMLScraper.section("Contesto", in: contextCard)
        #expect(contesto?.contains("Anno Accademico") == true)
        // Must stop at the next title, or every section contains the rest of
        // the page.
        #expect(contesto?.contains("Codice Identificativo") == false)
    }

    @Test("The detail carries context, facts and the programme apart")
    func detail() {
        let detail = ManifestoParser.detail(contextCard, code: "086214")
        #expect(detail?.code == "086214")
        #expect(detail?.name == "METODI ANALITICI E NUMERICI PER L'INGEGNERIA")
        #expect(detail?.context.count == 3)
        #expect(detail?.summary != nil)
        // The programme is prose and is not repeated among the key/value rows.
        #expect(detail?.facts.contains { $0.label.contains("Programma") } == false)
        #expect(detail?.facts.contains { $0.label.contains("Crediti") } == true)
    }

    // MARK: - Modules, scaglioni, teachers

    /// A real module row: bracket, code, name, teacher link, credits, period.
    private let moduleRows = """
    <TR><TD class="ElementInfoCard2">A</TD><TD class="ElementInfoCard2">ZZZZ</TD>
    <TD class="ElementInfoCard2">086213</TD>
    <TD class="ElementInfoCard2"><a href="/manifesti/manifesti/controller/ManifestoPublic.do?evn_dettaglio_modulo=evento&amp;c_insegn_d=086213&amp;lang=IT">METODI ANALITICI E NUMERICI PER L'INGEGNERIA (PARTE DI ANALISI NUMERICA)</a></TD>
    <TD class="ElementInfoCard2"><a href="/manifesti/manifesti/controller/ricerche/RicercaPerDocentiPublic.do?evn_didattica=evento&amp;k_doc=151967&amp;aa=2026&amp;lang=IT">Scotti Anna</a></TD>
    <TD class="ElementInfoCard2">5.0</TD><TD class="ElementInfoCard2">2&deg; sem</TD>
    <TD class="ElementInfoCard2"><a target="_blank" href="https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=178&amp;c_classe=889303"><img src="/manifesti/images/scheda.gif"></a></TD></TR>
    """

    @Test("A module row yields its code, teacher and credits")
    func module() {
        let modules = ManifestoParser.modules(moduleRows)
        #expect(modules.count == 1)
        #expect(modules[0].code == "086213")
        #expect(modules[0].teachers.first?.name == "Scotti Anna")
        #expect(modules[0].credits == 5.0)
    }

    /// `k_doc` is the catalogue's own teacher id — the name-to-id lookup that
    /// was missing when teacher search was built from course lists alone.
    @Test("The teacher's catalogue id is captured")
    func teacherID() {
        #expect(ManifestoParser.modules(moduleRows).first?.teachers.first?.kDoc == "151967")
    }

    /// `c_classe` is how the syllabus is reached, and it is hidden behind an
    /// icon with no text to key on.
    @Test("The syllabus id is found behind the icon link")
    func syllabusID() {
        #expect(ManifestoParser.modules(moduleRows).first?.syllabusID == "889303")
    }

    @Test("The alphabetical bracket is read as from-inclusive, to-exclusive")
    func scaglione() {
        let module = ManifestoParser.modules(moduleRows)[0]
        #expect(module.scaglioneFrom == "A")
        #expect(module.scaglioneTo == "ZZZZ")
    }

    /// The bracket decides a first-year student's lecturer and timetable, so
    /// the boundary behaviour has to be exactly what the page claims.
    @Test("A bracket includes its lower bound and excludes its upper")
    func bracketBounds() {
        let module = ManifestoModule(
            code: "1", name: "x", teachers: [], credits: nil, period: nil,
            language: nil, scaglioneFrom: "CAS", scaglioneTo: "FER", syllabusID: nil)
        #expect(module.covers(surname: "CAS"))
        #expect(module.covers(surname: "Casati"))
        #expect(module.covers(surname: "Dossena"))
        #expect(!module.covers(surname: "FER"))
        #expect(!module.covers(surname: "Ferrari"))
        #expect(!module.covers(surname: "Bianchi"))
    }

    /// Students type their own name the way they write it; the registry
    /// stores it shouted and unaccented.
    @Test("Bracket matching ignores case and accents")
    func bracketFolding() {
        let module = ManifestoModule(
            code: "1", name: "x", teachers: [], credits: nil, period: nil,
            language: nil, scaglioneFrom: "A", scaglioneTo: "M", syllabusID: nil)
        #expect(module.covers(surname: "dell'Acqua"))
        #expect(module.covers(surname: "Èboli"))
    }

    @Test("A module with no bracket covers everyone")
    func noBracket() {
        let module = ManifestoModule(
            code: "1", name: "x", teachers: [], credits: nil, period: nil,
            language: nil, scaglioneFrom: nil, scaglioneTo: nil, syllabusID: nil)
        #expect(module.covers(surname: "Qualunque"))
    }

    // MARK: - SSD

    @Test("The SSD table is read by the shape of its codes")
    func ssd() {
        let html = """
        <tr><td>A</td><td>MAT/08</td><td>ANALISI NUMERICA</td><td>5.0</td></tr>
        <tr><td>A</td><td>MAT/05</td><td>ANALISI MATEMATICA</td><td>5.0</td></tr>
        """
        let areas = ManifestoParser.ssd(html)
        #expect(areas.map(\.code) == ["MAT/08", "MAT/05"])
        #expect(areas[0].name == "ANALISI NUMERICA")
        #expect(areas[0].credits == 5.0)
        #expect(areas[0].kind == "A")
    }

    /// A six-digit teaching code must never be mistaken for a credit figure.
    @Test("Credits are only read from things shaped like credits")
    func creditShape() {
        #expect(ManifestoParser.credits(from: "10.0") == 10)
        #expect(ManifestoParser.credits(from: "5,0") == 5)
        #expect(ManifestoParser.credits(from: "086214") == nil)
        #expect(ManifestoParser.credits(from: "2026") == nil)
        #expect(ManifestoParser.credits(from: "2° sem") == nil)
    }

    // MARK: - Search

    @Test("A search row is identified by the link, not the columns")
    func searchResults() {
        let html = """
        <tr><td><a href="/manifesti/manifesti/controller/ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&amp;k_corso_la=352&amp;k_indir=E3N&amp;idItemOfferta=184998&amp;idRiga=354946&amp;codDescr=086214&amp;semestre=2&amp;aa=2026">METODI ANALITICI E NUMERICI</a></td><td>10.0</td></tr>
        """
        let results = ManifestoParser.searchResults(html)
        #expect(results.count == 1)
        #expect(results[0].code == "086214")
        #expect(results[0].courseCode == "352")
        #expect(results[0].planCode == "E3N")
        #expect(results[0].idRiga == "354946")
    }

    /// The same teaching appears once per module; the list must not repeat it.
    @Test("Repeated rows for one teaching collapse")
    func searchDeduplicates() {
        let row = """
        <tr><td><a href="/x.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&amp;k_corso_la=352&amp;k_indir=E3N&amp;codDescr=086214">NOME</a></td></tr>
        """
        #expect(ManifestoParser.searchResults(row + row).count == 1)
    }

    // MARK: - Syllabus

    /// Verbatim headings from the live scheda; the fallback path has to find
    /// them in document order when the CSS classes do not match.
    @Test("The syllabus is split into its named sections")
    func syllabus() {
        let html = """
        <div>Obiettivi dell'insegnamento</div>
        <p>Scopo di questo corso &egrave; introdurre gli strumenti.</p>
        <div>Argomenti trattati</div>
        <p>1: Fondamenti di calcolo numerico.</p>
        <div>Prerequisiti</div>
        <p>Analisi 1.</p>
        <div>Bibliografia</div>
        <p>Quarteroni, Matematica Numerica, Springer.</p>
        """
        let parsed = ManifestoParser.syllabus(html)
        #expect(!parsed.isEmpty)
        #expect(parsed.objectives?.contains("Scopo di questo corso") == true)
        #expect(parsed.topics?.contains("Fondamenti") == true)
        #expect(parsed.bibliography?.contains("Quarteroni") == true)
    }

    @Test("A page with none of the headings yields nothing rather than noise")
    func emptySyllabus() {
        #expect(ManifestoParser.syllabus("<p>Pagina di ricerca</p>").isEmpty)
    }

    // MARK: - Academic years

    @Test("Academic years are labelled as the catalogue labels them")
    func years() {
        #expect(AcademicYear(code: "2026").label == "2026/2027")
        let list = AcademicYear.recent(
            from: Date(timeIntervalSince1970: 1_789_000_000))   // 2026-09
        #expect(list.count == 6)
        #expect(list.first?.code == "2026")
    }
}
