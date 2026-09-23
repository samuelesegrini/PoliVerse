import Foundation
import Testing
@testable import PoliVerse

/// Reading the recman archive's list page.
///
/// The fixture follows the page as captured on 2026-09-23: a layout table around
/// the filters, then the list with its headers and one row per recording, the
/// play link in the first cell. Names and tokens are replaced.
@Suite("Lettura dell’archivio registrazioni")
struct RecmanParserTests {
    /// The list page, trimmed to what the parser reads.
    private let page = """
    <html><body>
    <table class="Layout"><tr><td>
      <table><tr><td>MARIO ROSSI 123456 Logout (archivio)</td></tr></table>
      <form action="/recman_frontend/recman_frontend/controller/ArchivioListActivity.do?jaf_currentWFID=1&amp;polij_step=0&amp;__pj0=0&amp;__pj1=abc">
      <table>
        <tr><td>Filtri</td><td>Anno Accademico</td><td><select name="aa"><option value="">Tutti</option><option value="2026">2026 / 27</option></select></td></tr>
        <tr><td>Corso</td><td><input name="contesto"></td></tr>
        <tr><td><input type="submit" name="EVN_SEARCH" value="Cerca"></td></tr>
      </table>
      </form>
    <table class="TableDati">
      <thead><tr>
        <th>Riproduci</th><th>Anno Accademico</th><th>Data Registrazione</th><th>Corso</th>
        <th>Forma didattica</th><th>Argomento</th><th>Ospiti</th><th>Durata</th><th>Dimensione</th>
      </tr></thead>
      <tbody class="TableDati-tbody">
        <tr class="TableDati-tbody-tr">
          <td><a href="/recman_frontend/recman_frontend/controller/ArchivioListActivity.do?evn_preview_link=evento&amp;transfer_id=164744&amp;jaf_currentWFID=1&amp;polij_step=0&amp;__pj0=0&amp;__pj1=abc" title="Riproduci" class="Link" target="_blank"><img src="play.png"></a></td>
          <td>2026 / 27</td><td>21/09/2026 13:34</td>
          <td>090950 - DISTRIBUTED SYSTEMS (VERDI&nbsp;GIULIA)</td>
          <td>Lezione</td><td>Message oriented communication</td><td></td><td>135 min</td><td>198 MB</td>
        </tr>
        <tr class="TableDati-tbody-tr">
          <td><a href="/recman_frontend/recman_frontend/controller/ArchivioListActivity.do?evn_preview_link=evento&amp;transfer_id=164234&amp;jaf_currentWFID=1&amp;polij_step=0&amp;__pj0=0&amp;__pj1=abc" title="Riproduci" class="Link" target="_blank"><img src="play.png"></a></td>
          <td>2026 / 27</td><td>18/09/2026 08:27</td>
          <td>090950 - DISTRIBUTED SYSTEMS (VERDI GIULIA)</td>
          <td>Esercitazione</td><td></td><td></td><td>94 min</td><td>140 MB</td>
        </tr>
      </tbody>
    </table>
    </td></tr></table>
    </body></html>
    """

    @Test("Ogni riga con il collegamento diventa una registrazione")
    func rows() throws {
        let rows = RecmanParser.rows(in: page)
        #expect(rows.map(\.recording.transferID) == [164744, 164234])

        let first = try #require(rows.first?.recording)
        #expect(first.teachingCode == "090950")
        #expect(first.courseTitle == "DISTRIBUTED SYSTEMS")
        #expect(first.lecturer == "VERDI GIULIA", "Lo spazio non separabile diventa uno spazio")
        #expect(first.academicYear == "2026/27")
        #expect(first.form == .lecture)
        #expect(first.topic == "Message oriented communication")
        #expect(first.minutes == 135)
        #expect(first.megabytes == 198)

        let components = PoliMiDate.romeCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: first.recordedAt)
        #expect(components.day == 21 && components.month == 9 && components.year == 2026)
        #expect(components.hour == 13 && components.minute == 34, "L'ora è quella di Roma")
    }

    @Test("Un argomento vuoto resta assente, e la forma si legge comunque")
    func emptyTopic() throws {
        let second = try #require(RecmanParser.rows(in: page).last?.recording)
        #expect(second.topic == nil)
        #expect(second.form == .exercise)
    }

    /// The link carries the session's tokens; it must come back usable, with its
    /// entities decoded and resolved against the host.
    @Test("Il collegamento di riproduzione è assoluto e decodificato")
    func playLink() throws {
        let link = try #require(RecmanParser.rows(in: page).first?.playLink)
        #expect(link.host == "onlineservices.polimi.it")
        #expect(link.absoluteString.contains("evn_preview_link=evento&transfer_id=164744&"))
        #expect(!link.absoluteString.contains("&amp;"))
    }

    /// The filters sit in layout rows before the list; a regex pairing the first
    /// `<tr>` with the first `</tr>` would swallow them into a recording.
    @Test("Le righe dei filtri e dell'impaginazione non diventano registrazioni")
    func layoutRowsIgnored() {
        #expect(RecmanParser.rows(in: page).count == 2)
    }

    @Test("La pagina si riconosce come archivio, anche vuota")
    func recognisesArchive() {
        #expect(RecmanParser.isArchive(page))
        let empty = page.replacingOccurrences(
            of: #"(?s)<tbody class="TableDati-tbody">.*</tbody>"#, with: "<tbody></tbody>", options: .regularExpression)
        #expect(RecmanParser.isArchive(empty))
        #expect(RecmanParser.rows(in: empty).isEmpty)
        #expect(!RecmanParser.isArchive("<html><body>Errore interno</body></html>"))
    }

    /// Without headers, the columns fall back to the order the page has used.
    @Test("Senza intestazioni valgono le posizioni consuete")
    func withoutHeaders() {
        let bare = page.replacingOccurrences(of: #"(?s)<thead>.*</thead>"#, with: "", options: .regularExpression)
        #expect(!bare.contains("<th>"), "Il fixture ha davvero perso le intestazioni")
        let recording = RecmanParser.rows(in: bare).first?.recording
        #expect(recording?.teachingCode == "090950")
        #expect(recording?.minutes == 135)
    }

    @Test("Il corso si divide in codice, titolo e docente")
    func course() {
        let plain = RecmanParser.parseCourse("052496 - ANALISI MATEMATICA 1")
        #expect(plain?.code == "052496")
        #expect(plain?.title == "ANALISI MATEMATICA 1")
        #expect(plain?.lecturer == nil)

        let nested = RecmanParser.parseCourse("095948 - FONDAMENTI (MOD. A) (ROSSI MARIO)")
        #expect(nested?.title == "FONDAMENTI (MOD. A)", "Solo l'ultima parentesi è il docente")
        #expect(nested?.lecturer == "ROSSI MARIO")

        #expect(RecmanParser.parseCourse("DISTRIBUTED SYSTEMS")?.code == nil, "Senza codice la riga non si collega")
    }

    @Test("Il vecchio reindirizzamento via script si legge ancora")
    func scriptedRedirect() {
        let html = "<script>location.href='https://politecnicomilano.webex.com/politecnicomilano/ldr.php?RCID=abc';</script>"
        #expect(RecmanParser.scriptedRedirect(in: html)?.host == "politecnicomilano.webex.com")
    }

    @Test("Le registrazioni si collegano al corso per codice")
    func joinsCourse() {
        var course = Course(id: "090950", name: "Distributed Systems", teacher: "—", cfu: 10,
                            semester: "1", academicYear: "2026/27")
        course.code = "090950"
        let recordings = RecmanParser.rows(in: page).map(\.recording)
        #expect(Recording.of(course, in: recordings).map(\.transferID) == [164744, 164234])

        let unrelated = Course(id: "052496", name: "Analisi", teacher: "—", cfu: 10, semester: "1", academicYear: "2026/27")
        #expect(Recording.of(unrelated, in: recordings).isEmpty)
    }

    /// The body must match what the official app sends, key for key: the endpoint
    /// validates it, and a renamed key is a refusal nobody can read.
    @Test("Il salto verso recman chiede il servizio con le chiavi dell'app ufficiale")
    func jumpBody() throws {
        let request = RecmanJump.request(matricola: "123456")
        #expect(request.method == "POST")
        #expect(request.path == "/jaf/public/linksalto")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["target_service_id"] as? Int == 2314)
        #expect(json["return_url"] is String)
        let params = try #require(json["params"] as? [String: Any])
        #expect(params["al_pj_matricola"] as? String == "123456")
        #expect(params["polij_device_category"] as? String == "DESKTOP")
        #expect(params["polij_into_webview"] as? Bool == false)
        #expect(params["al_id_srv_chiamante"] as? String == "2428")

        let answer = try JSONDecoder().decode(
            RecmanJump.Answer.self, from: Data(#"{"jump_url":"https://aunicalogin.polimi.it/x?ticket=t"}"#.utf8))
        #expect(answer.url?.host == "aunicalogin.polimi.it")
    }

    /// The empty list before its search, as the English interface serves it: no
    /// rows, no Italian headers, only the search form posting back to the list.
    @Test("La pagina vuota prima della ricerca si riconosce anche in inglese")
    func emptyEnglishArchive() {
        let html = """
        <title>Recordings archives</title>
        <form action="/recman_frontend/recman_frontend/controller/ArchivioListActivity.do?jaf_currentWFID=1">
          <select name="aa"><option value="">All</option></select>
          <input type="submit" name="EVN_SEARCH" value="Search">
        </form>
        """
        #expect(RecmanParser.isArchive(html))
        #expect(RecmanParser.rows(in: html).isEmpty)
        #expect(Recording.Form(label: "Lecture") == .lecture)
    }

    /// The log line for a page that did not read must not carry the student's name,
    /// which every recman page shows in its header.
    @Test("Il riassunto per il log non riporta il testo della pagina")
    func gistHasNoText() {
        let gist = RecmanBrowser.gist(of: page)
        #expect(!gist.contains("MARIO ROSSI"))
        #expect(gist.contains("Data Registrazione"))
        #expect(gist.contains("EVN_SEARCH"))
    }

    /// A WeBeep course page carries its "Registrazioni" link as a URL module; that is
    /// the backup way into recman.
    @Test("Il link Registrazioni di WeBeep si trova tra i moduli URL")
    func weBeepEntry() throws {
        func module(_ modname: String, _ url: String) -> MoodleModule {
            MoodleModule(id: 1, name: "Registrazioni", modname: modname, contents: [
                MoodleContent(type: "url", filename: nil, filesize: nil, fileurl: url, timemodified: nil, mimetype: nil)])
        }
        let sections = [
            MoodleSection(id: 1, name: "Generale", modules: [
                module("resource", "https://webeep.polimi.it/pluginfile.php/1/slides.pdf"),
                module("url", "https://aunicalogin.polimi.it/aunicalogin/getservizio.xml?id_servizio=2294&c_classe_webeep=888574-STD"),
            ]),
        ]
        let entry = try #require(RecmanParser.courseEntry(in: sections))
        #expect(entry.absoluteString.contains("c_classe_webeep=888574-STD"))
        #expect(entry.absoluteString.hasSuffix("lang=IT"))
        #expect(RecmanParser.courseEntry(in: [MoodleSection(id: 2, name: "Vuota", modules: [])]) == nil)
    }

    /// A course's own page may not name the course in each row; its rows are filed
    /// under the course the link came from.
    @Test("Senza codice nella riga vale quello del corso da cui si arriva")
    func fallbackCode() {
        let page = self.page.replacingOccurrences(of: "090950 - ", with: "")
        #expect(RecmanParser.rows(in: page).isEmpty)
        #expect(RecmanParser.rows(in: page, fallbackCode: "090950").map(\.recording.teachingCode) == ["090950", "090950"])
    }

    /// The list as recman serves it today, read back from a run on 2026-09-23: each
    /// cell writes its column's name above its value, length and size share the
    /// Durata cell, the play link sits in the last cell, and the headers say "Data".
    private let labelledPage = """
    <table class="TableDati">
      <thead><tr><th>Anno Accademico</th><th>Data</th><th>Corso</th><th>Forma didattica</th>
        <th>Argomento</th><th>Ospiti</th><th>Durata</th></tr></thead>
      <tbody class="TableDati-tbody">
        <tr>
          <td><div class="lbl">Anno Accademico</div><div>2026 / 27</div></td>
          <td><div class="lbl">Data</div><div>21/09/2026 13:34</div></td>
          <td><div class="lbl">Corso</div><div>090950 - DISTRIBUTED SYSTEMS (VERDI GIULIA)</div></td>
          <td><div class="lbl">Forma didattica</div><div>Lezione</div></td>
          <td><div class="lbl">Argomento</div><div>Message oriented communication</div></td>
          <td><div class="lbl">Ospiti</div><div></div></td>
          <td><div class="lbl">Durata</div><div>135 min / 198 MB</div></td>
          <td><a href="/recman_frontend/recman_frontend/controller/ArchivioListActivity.do?evn_preview_link=evento&amp;transfer_id=164744&amp;jaf_currentWFID=1" class="Link">Riproduci</a></td>
        </tr>
      </tbody>
    </table>
    """

    @Test("Le celle con l'etichetta sopra il valore si leggono per etichetta")
    func labelledCells() throws {
        let recording = try #require(RecmanParser.rows(in: labelledPage).first?.recording)
        #expect(recording.transferID == 164744)
        #expect(recording.academicYear == "2026/27")
        #expect(recording.teachingCode == "090950")
        #expect(recording.form == .lecture)
        #expect(recording.topic == "Message oriented communication")
        #expect(recording.minutes == 135)
        #expect(recording.megabytes == 198, "La dimensione sta nella cella della durata")
        let components = PoliMiDate.romeCalendar.dateComponents([.day, .hour, .minute], from: recording.recordedAt)
        #expect(components.day == 21 && components.hour == 13 && components.minute == 34)
    }

    @Test("La dimensione si legge in MB e in GB")
    func megabytes() {
        #expect(RecmanParser.parseMegabytes("168 min / 649 MB") == 649)
        #expect(RecmanParser.parseMegabytes("1,5 GB") == 1536)
        #expect(RecmanParser.parseMegabytes("135 min") == nil)
    }

    /// The kept session must come back as the cookie that was served: same name,
    /// value, host and flags, and still session-only.
    @Test("Un cookie tenuto nel Portachiavi torna com'era")
    func keptCookie() throws {
        let original = try #require(HTTPCookie(properties: [
            .name: "SSO_LOGIN", .value: "abc", .domain: "aunicalogin.polimi.it", .path: "/",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE",
        ]))
        let kept = RecordingsWebKit.KeptCookie(original)
        let data = try JSONEncoder().encode(kept)
        let back = try #require(try JSONDecoder().decode(RecordingsWebKit.KeptCookie.self, from: data).cookie)
        #expect(back.name == "SSO_LOGIN" && back.value == "abc" && back.domain == "aunicalogin.polimi.it")
        #expect(back.isSecure && back.isHTTPOnly)
        #expect(back.isSessionOnly)
    }

    /// The fields the app reads from Webex's `/stream` answer, as captured on
    /// 2026-09-23 (addresses shortened, tokens removed).
    @Test("La risposta /stream di Webex si legge: HLS, durata e permessi")
    func webexStream() throws {
        let json = """
        {"downloadRecordingInfo":{"downloadInfo":{
            "hlsURL":"https://nfg1wss.webex.com/nbr/MultiThreadDownloadServlet/abc/hls.m3u8",
            "mp4URL":"https://nfg1wss.webex.com/nbr/MultiThreadDownloadServlet?recordid=1"},"recordUUID":"x"},
         "duration":8122000,"fileSize":207944795,"preventDownload":false,"enforcePreventDownload":false,
         "needShowDisclaimer":true,"recordName":"Lezione","canPlayback":true}
        """
        let stream = try JSONDecoder().decode(WebexStream.self, from: Data(json.utf8))
        #expect(stream.hlsURL?.lastPathComponent == "hls.m3u8")
        #expect(stream.duration == .milliseconds(8_122_000))
        #expect(stream.fileSize == 207_944_795)
        #expect(stream.allowsDownload)
        #expect(stream.needsDisclaimer)

        let locked = try JSONDecoder().decode(WebexStream.self, from: Data(
            #"{"downloadRecordingInfo":{"downloadInfo":{"hlsURL":"https://x/hls.m3u8","mp4URL":"https://x/y"}},"preventDownload":false,"enforcePreventDownload":true}"#.utf8))
        #expect(!locked.allowsDownload, "Il divieto del sito vale quanto quello del docente")

        let bare = try JSONDecoder().decode(WebexStream.self, from: Data("{}".utf8))
        #expect(bare.hlsURL == nil && !bare.allowsDownload)
    }
}
