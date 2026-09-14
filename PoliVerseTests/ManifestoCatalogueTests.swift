import Foundation
import Testing
@testable import PoliVerse

/// The manifesto's own cascade — anno, sede, scuola, corso di studi, piano —
/// and the plan page's teachings, from live markup of 2026-09-14
/// (`ManifestoPublic.do`, Ingegneria Informatica 531, plan IT1).
@Suite("Manifesto catalogue")
struct ManifestoCatalogueTests {
    private let form = """
    <TABLE width="100%" class="BoxInfoCard" cellspacing="0" cellpadding="5" id="id_combocds">  <TBODY><TR><TD class='ElementInfoCard1 left' width='15%'>Anno Accademico</TD><TD class='ElementInfoCard2 left' width='15%'><select name="aa" width='100%' STYLE="WIDTH:100%"onchange=changeOnClick()><option value="2026" SELECTED>2026/2027</option><option value="2025" >2025/2026</option></select></TD><TD class='ElementInfoCard1 left' width='15%'>Sede</TD><TD class='ElementInfoCard2 left' colspan='1'width='55%'><select name="sede" width='100%' STYLE="WIDTH:100%"onchange=changeOnClick()><option value="ALL_SEDI" >Qualunque sede</option><option value="CO" >Como (CO)</option><option value="MI" SELECTED>Milano Leonardo (MI)</option></select></TD></TR><TR><TD class='ElementInfoCard1 left' width='15%'>Scuola</TD><TD class='ElementInfoCard2 left' colspan='3'width='85%'><select name="k_cf" width="100%" style="width:100%" onchange=changeOnClick()><option value="222" >Scuola di Architettura Urbanistica Ingegneria delle Costruzioni (Arc. Urb. Ing. Cos.)</option><option value="225" SELECTED>Scuola di Ingegneria Industriale e dell'Informazione (Ing. Ind-Inf)</option></select></TD></TR><TR><TD class='ElementInfoCard1 left' width='15%'>Corso di Studi</TD><TD class='ElementInfoCard2 left' colspan='3'width='85%'><select name="k_corso_la" width="100%" style="width:100%" onchange=changeOnClick()><optgroup label="Laurea di Primo Livello - ord. 96/23"><option value="571" >Engineering Science (571)</option><option value="531" SELECTED>Ingegneria Informatica (531)</option></optgroup><optgroup label="Laurea Magistrale - ord. 96/23"><option value="1077" >Biomedical Engineering (1077)</option></optgroup></select></TD></TR><TR><TD class='ElementInfoCard1 left' width='15%'>Anno Corso</TD><TD class='ElementInfoCard2 left' width='15%'><select name="ac_ins" width="100%" style="width:100%" onchange=changeOnClick()><option value="0" SELECTED>Tutti</option><option value="1" >1</option></select></TD><TD class='ElementInfoCard1 left' width='15%'>Piano di Studio preventivamente approvato</TD><TD class='ElementInfoCard2 left' colspan='1'width='55%'><select name="k_indir" style="width: 100%;" style="width:100%" onchange="changeOnClick()"><option value="IT1" SELECTED>IT1 - Ingegneria Informatica e Comunicazioni</option><option value="IOL" >IOL - Ingegneria Informatica Online</option></SELECT>Sede: Milano Leonardo<br>Lingua Offerta: Italiano</TD></TR></TBODY></TABLE>
    """

    /// Lecco, Design: a level with one choice is written as text and a hidden input.
    private let hidden = """
    <TR><TD class='ElementInfoCard1 left' width='15%'>Corso di Studi</TD><TD class='ElementInfoCard2 left' colspan='3'width='85%'>(1 liv.)(ord. 96/23) - LC (1014) Interaction Design<input type="hidden" name="k_corso_la" value="1014"></TD></TR>
    """

    private let rows = """
    <TD class="TitleInfoCard">1<sup><small>o</small></sup>Anno</TD>
    <tr><TD width="5%" class="ElementInfoCard2" style="text-align:center">082740</TD><TD width="10%" class="ElementInfoCard2" style="text-align:center">MATH-03/A</TD><TD width="10%" class="ElementInfoCard2" style="text-align:center">MAT/05</TD><TD width="5%" class="ElementInfoCard2 orario_td no_sezioni" style="text-align:center"><a name="2026531IT110827401"href="/manifesti/manifesti/controller/ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&aa=2026&k_cf=225&k_corso_la=531&k_indir=IT1&codDescr=082740&lang=IT&semestre=1&anno_corso=1&idItemOfferta=181354&idRiga=344049"><img style="vertical-align:middle" src="/manifesti/images/cart/cart_put.png" border="none" height="16"></a></TD><TD colspan="3" width="44%" class="ElementInfoCard2" style="text-align:left"><a href="/manifesti/manifesti/controller/ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&aa=2026&k_cf=225&k_corso_la=531&k_indir=IT1&codDescr=082740&lang=IT&semestre=1&anno_corso=1&idItemOfferta=181354&idRiga=344049">ANALISI MATEMATICA 1</a></TD><TD width="5%" class="ElementInfoCard2" style="text-align:center"><img border="none" height="16" src="/manifesti/images/flag_collection/it.png"></TD><TD width="5%" class="ElementInfoCard2" style="text-align:center">MI</TD><TD width="5%" class="ElementInfoCard2" style="text-align:center">M</TD><TD width="5%" class="ElementInfoCard2" style="text-align:center">1° sem</TD><TD width="5%" class="ElementInfoCard2" style="text-align:center">10.0</TD></tr>
    <TD class="TitleInfoCard">3<sup><small>o</small></sup>Anno</TD>
    <td class="TitleInfoCard">Insegnamenti del Gruppo  TABA</td>
    <tr><TD width="5%" class="ElementInfoCard1" style="text-align:center">058084</TD><TD width="10%" class="ElementInfoCard1" style="text-align:center">IINF-02/A</TD><TD width="10%" class="ElementInfoCard1" style="text-align:center">ING-INF/02</TD><TD width="5%" class="ElementInfoCard1 orario_td no_sezioni" style="text-align:center"><a name="2026531IT10580841"href="/manifesti/manifesti/controller/ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&aa=2026&k_cf=225&k_corso_la=531&k_indir=IT1&codDescr=058084&lang=IT&semestre=1&idGruppo=5653&idRiga=344060"><img src="/manifesti/images/cart/cart_put.png" border="none" height="16"></a></TD><TD colspan="3" class="ElementInfoCard1" style="text-align:left"><a href="/manifesti/manifesti/controller/ManifestoPublic.do?EVN_DETTAGLIO_RIGA_MANIFESTO=evento&aa=2026&k_cf=225&k_corso_la=531&k_indir=IT1&codDescr=058084&lang=IT&semestre=1&idGruppo=5653&idRiga=344060">ONDE ELETTROMAGNETICHE E MEZZI TRASMISSIVI</a></TD><TD width="5%" class="ElementInfoCard1" style="text-align:center"><img border="none" height="16" src="/manifesti/images/flag_collection/it.png"></TD><TD width="5%" class="ElementInfoCard1" style="text-align:center">MI</TD><TD width="5%" class="ElementInfoCard1" style="text-align:center">M</TD><TD width="5%" class="ElementInfoCard1" style="text-align:center">1° sem</TD><TD width="5%" class="ElementInfoCard1" style="text-align:center">5.0</TD></tr>
    """

    @Test("Each level reads its options, groups and the choice the page made")
    func levels() throws {
        let page = try #require(CatalogueParser.page(form + rows))
        let campus = try #require(page.level(.campus))
        #expect(campus.options.map(\.value) == ["ALL_SEDI", "CO", "MI"])
        #expect(campus.selected == "MI")
        let degree = try #require(page.level(.degree))
        #expect(degree.selected == "531")
        #expect(degree.options.map(\.group) == ["Laurea di Primo Livello - ord. 96/23", "Laurea di Primo Livello - ord. 96/23",
                                               "Laurea Magistrale - ord. 96/23"])
        #expect(page.level(.plan)?.options.first?.label == "IT1 - Ingegneria Informatica e Comunicazioni")
        #expect(page.selection == CatalogueSelection(year: "2026", campus: "MI", school: "225", degree: "531", plan: "IT1"))
    }

    @Test("A level with a single choice is read from its hidden input")
    func hiddenLevel() throws {
        let only = try #require(CatalogueParser.level(.degree, in: hidden))
        #expect(only.options.map(\.value) == ["1014"])
        #expect(only.options.first?.label == "(1 liv.)(ord. 96/23) - LC (1014) Interaction Design")
        #expect(only.selected == "1014")
    }

    /// Live, Architecture school 2026: "*** - Non diversificato" can be chosen
    /// and lists nothing; the real plans sit beside it.
    @Test("The empty non-differentiated plan is not offered when real plans exist")
    func nonDifferentiated() throws {
        let html = #"<select name="k_indir"><option value="***" SELECTED>*** - Non diversificato</option><option value="IE1" >IE1 - Curriculum - IEC</option></SELECT>"#
        let level = try #require(CatalogueParser.level(.plan, in: html))
        #expect(level.options.map(\.value) == ["IE1"])
        #expect(level.selected == "***")
        let only = try #require(CatalogueParser.level(.plan, in: #"<select name="k_indir"><option value="***" SELECTED>*** - Non diversificato</option></select>"#))
        #expect(only.options.map(\.value) == ["***"])
    }

    @Test("The service's error page is no page")
    func errorPage() {
        #expect(CatalogueParser.page("<html><body><a href='x'>Errore interno, fai click per effettuare il logout e ricominciare</a></body></html>") == nil)
    }

    @Test("Teachings take their year of course from the heading above them")
    func teachings() throws {
        let page = try #require(CatalogueParser.page(form + rows))
        #expect(page.teachings.map(\.teaching.code) == ["082740", "058084"])
        #expect(page.teachings.map(\.yearOfCourse) == ["1", "3"])
        #expect(page.teachings.map(\.group) == [nil, "TABA"])
        let first = try #require(page.teachings.first)
        #expect(first.teaching.name == "ANALISI MATEMATICA 1")
        #expect(first.teaching.courseCode == "531")
        #expect(first.teaching.planCode == "IT1")
        #expect(first.teaching.semester == "1")
        #expect(first.credits == 10)
        #expect(first.hasSections == false)
        #expect(first.cartLink == PersonalTimetableParser.CartLink(courseCode: "531", planCode: "IT1", semester: "1", yearOfCourse: "1"))
    }

    @Test("The query sends every level: the service fails when one is missing")
    func query() {
        let selection = CatalogueSelection(year: "2026", campus: "MI", school: "225", degree: "531", plan: "IT1")
        let items = Dictionary(uniqueKeysWithValues: selection.queryItems.map { ($0.name, $0.value ?? "") })
        #expect(items["aa"] == "2026" && items["sede"] == "MI" && items["k_cf"] == "225")
        #expect(items["k_corso_la"] == "531" && items["k_indir"] == "IT1" && items["ac_ins"] == "0")
        #expect(items["evn_default"] != nil)
    }

    @Test("Changing a level keeps what is above it and lets the service settle what is below")
    func changing() {
        let selection = CatalogueSelection(year: "2026", campus: "MI", school: "225", degree: "531", plan: "IT1")
        #expect(selection.setting(.campus, to: "LC") == CatalogueSelection(year: "2026", campus: "LC", school: "225", degree: "531", plan: "IT1"))
        #expect(selection.setting(.plan, to: "IOL").plan == "IOL")
    }
}

/// One cart per bracket: setting a name empties the Politecnico's cart, and
/// the bracket is decided by the name set when the timetable is read.
@Suite("Cart batches")
struct CartBatchTests {
    private func teaching(_ code: String) -> ManifestoTeaching {
        ManifestoTeaching(code: code, name: code, courseCode: "531", planCode: "IT1", idItemOfferta: nil, idRiga: nil,
                          semester: "1", year: "2026", credits: nil, school: nil, degreeCourse: nil)
    }

    @Test("Teachings without a chosen bracket go under the student's name, first")
    func ownName() {
        let batches = CartBatches.batches(name: "Rossi Mario", surname: "Rossi", teachings: [teaching("1"), teaching("2")], brackets: [:])
        #expect(batches.map(\.cartName) == ["Rossi Mario"])
        #expect(batches.first?.teachings.map(\.code) == ["1", "2"])
    }

    @Test("A different bracket gets its own cart, named by where the bracket starts")
    func otherBracket() {
        let brackets = ["2": BracketChoice(from: "CON ", to: "FOT", teachers: ["De Martino"]),
                        "3": BracketChoice(from: "CON", to: "FOT", teachers: []),
                        "4": BracketChoice(from: "RET", to: "TOS", teachers: [])]
        let batches = CartBatches.batches(name: "Rossi Mario", surname: "Rossi",
                                          teachings: [teaching("1"), teaching("2"), teaching("3"), teaching("4")],
                                          brackets: brackets)
        #expect(batches.map(\.cartName) == ["Rossi Mario", "CON A"])
        #expect(batches.map { $0.teachings.map(\.code) } == [["1", "4"], ["2", "3"]])
    }

    @Test("A bracket starting at A still resolves to the first bracket")
    func first() {
        let batches = CartBatches.batches(name: "Zanetti Luca", surname: "Zanetti", teachings: [teaching("1")],
                                          brackets: ["1": BracketChoice(from: "A", to: "BRU", teachers: [])])
        #expect(batches.map(\.cartName) == ["A A"])
        #expect(ManifestoModule(code: "1", name: "", teachers: [], credits: nil, period: nil, language: nil,
                                scaglioneFrom: "A", scaglioneTo: "BRU", syllabusID: nil).covers(surname: "A"))
    }
}
