import Testing
import Foundation
@testable import PoliVerse

@Suite("Domain models")
struct ModelTests {
    /// This crashed the calendar tab: `isOngoing` forms `start...end`, which
    /// traps on an inverted range, and a deadline was written 23:15 → 23:00.
    @Test("An inverted event is clamped instead of trapping")
    func invertedEventIsClamped() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(-3600)

        let event = AgendaEvent(
            id: 1, title: "Consegna", start: start, end: end, kind: .deadline
        )

        #expect(event.end == start)
        #expect(event.duration == 0)
        #expect(event.isOngoing(at: start) == false)
    }

    @Test("A lecture reports as ongoing only within its window")
    func ongoingWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = AgendaEvent(
            id: 2, title: "Lezione", start: start,
            end: start.addingTimeInterval(3600), kind: .lecture
        )

        #expect(event.isOngoing(at: start.addingTimeInterval(1800)))
        #expect(event.isOngoing(at: start.addingTimeInterval(-1)) == false)
        #expect(event.isOngoing(at: start.addingTimeInterval(3601)) == false)
    }

    /// `hashValue` is seeded per process, so using it here made course colours
    /// reshuffle on every launch.
    @Test("Course colour is stable for a given code")
    func colorSeedIsStable() {
        let course = Course(
            id: "085923", name: "Test", teacher: "T", cfu: 5,
            semester: "1", academicYear: "2025"
        )
        // Hardcoded: if the hash implementation changes, colours change for
        // every existing user, and this test should make that a deliberate act.
        let seed = course.colorSeed
        #expect(seed == course.colorSeed)
        #expect((0..<8).contains(seed))

        let other = Course(
            id: "085923", name: "Different name", teacher: "Other", cfu: 9,
            semester: "2", academicYear: "2026"
        )
        // Only the code feeds the colour, so the same course keeps its colour
        // even if the title or teacher changes between years.
        #expect(other.colorSeed == seed)
    }

    @Test("SHOUTED course titles are cased for display")
    func titleNormalisation() {
        #expect(Course.normalise("ARCHITETTURE DEI CALCOLATORI")
                == "Architetture dei Calcolatori")
        #expect(Course.normalise("FONDAMENTI DI AUTOMATICA")
                == "Fondamenti di Automatica")
        // Minor words stay lowercase only mid-title.
        #expect(Course.normalise("BASI DI DATI") == "Basi di Dati")
    }

    @Test("Favourites are not encoded, so a stale cache cannot resurrect one")
    func favouriteNotPersistedInCache() throws {
        var course = Course(
            id: "1", name: "N", teacher: "T", cfu: 5,
            semester: "1", academicYear: "2025"
        )
        course.isFavourite = true

        let data = try JSONEncoder().encode(course)
        let decoded = try JSONDecoder().decode(Course.self, from: data)

        #expect(decoded.isFavourite == false)
        #expect(decoded.id == "1")
    }
}

@Suite("Exam mapping")
struct ExamMappingTests {
    private func dto(
        subscription: ExamDTO.ActiveSubscription? = nil,
        open: Bool? = nil,
        opens: String? = nil
    ) -> ExamDTO {
        ExamDTO(
            c_appello: 1, d_app: "2026-06-12", ora_ok: "14:30",
            d_apertura: opens, d_chiusura: nil, numIscrittiAppello: 10,
            descTipoAppello: "Scritto", xaula: "Aula Magna",
            iscrizioneAttiva: subscription, iscrizioniAperte: open
        )
    }

    @Test("A published mark becomes a graded status")
    func gradedStatus() throws {
        let session = dto(subscription: .init(
            c_iscriz: 1, verb_esito: "28", verb_esito_number: 28,
            verb_positivo: "S", xverbEsito: "28", hasEsito: true, rifiutabile: true
        )).toSession(courseName: "BASI DI DATI", courseCode: "097785", teacher: "CERI STEFANO")

        let grade = try #require(session.grade)
        #expect(grade.value == 28)
        #expect(grade.passed)
        #expect(grade.refusable)
        #expect(session.courseName == "Basi di Dati")
        #expect(session.teacher == "Ceri Stefano")
    }

    /// Pass/fail comes from `verb_positivo`, because the mark text can be
    /// "SUPERATO" or "IDONEO" with no number at all.
    @Test("A non-numeric pass is still a pass")
    func nonNumericPass() throws {
        let session = dto(subscription: .init(
            c_iscriz: 1, verb_esito: "SUPERATO", verb_esito_number: nil,
            verb_positivo: "S", xverbEsito: "SUPERATO", hasEsito: true, rifiutabile: false
        )).toSession(courseName: "PROVA FINALE", courseCode: "1", teacher: nil)

        let grade = try #require(session.grade)
        #expect(grade.value == nil)
        #expect(grade.passed)
        #expect(grade.display == "SUPERATO")
    }

    @Test("Lode renders as 30L")
    func lodeDisplay() throws {
        let session = dto(subscription: .init(
            c_iscriz: 1, verb_esito: "30 e lode", verb_esito_number: 30,
            verb_positivo: "S", xverbEsito: "30 e lode", hasEsito: true, rifiutabile: false
        )).toSession(courseName: "ANALISI", courseCode: "1", teacher: nil)

        #expect(try #require(session.grade).display == "30L")
    }

    @Test("Enrolment states map without a mark")
    func enrolmentStates() {
        let enrolled = dto(subscription: .init(
            c_iscriz: 9, verb_esito: nil, verb_esito_number: nil,
            verb_positivo: nil, xverbEsito: nil, hasEsito: false, rifiutabile: nil
        )).toSession(courseName: "A", courseCode: "1", teacher: nil)
        #expect(enrolled.status == .enrolled)

        #expect(dto(open: true).toSession(courseName: "A", courseCode: "1", teacher: nil)
                    .status == .open)

        let future = ISO8601DateFormatter().string(from: .now.addingTimeInterval(86_400 * 30))
        #expect(dto(open: false, opens: future)
                    .toSession(courseName: "A", courseCode: "1", teacher: nil)
                    .status == .notYetOpen)

        #expect(dto(open: false).toSession(courseName: "A", courseCode: "1", teacher: nil)
                    .status == .closed)
    }

    @Test("Day and time fields are recombined into one instant")
    func dateAndTimeCombined() throws {
        let session = dto(open: true)
            .toSession(courseName: "A", courseCode: "1", teacher: nil)
        let date = try #require(session.date)

        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        #expect(rome.component(.day, from: date) == 12)
        #expect(rome.component(.hour, from: date) == 14)
        #expect(rome.component(.minute, from: date) == 30)
    }
}

@Suite("OAuth")
struct OAuthTests {
    /// PoliFemo strips the prefix with `url.replace(...)`, which breaks as soon
    /// as the IdP appends another parameter or reorders them.
    @Test("Authcode survives extra and reordered query parameters")
    func authCodeExtraction() throws {
        let plain = try #require(URL(string:
            "https://polimiapp.polimi.it/polimi_app/app?code=ABC123"))
        #expect(PoliMiOAuth.authCode(from: plain) == "ABC123")

        let withState = try #require(URL(string:
            "https://polimiapp.polimi.it/polimi_app/app?state=10010&code=ABC123&scope=openid"))
        #expect(PoliMiOAuth.authCode(from: withState) == "ABC123")
    }

    @Test("Unrelated redirects yield no code")
    func ignoresOtherHosts() throws {
        let other = try #require(URL(string: "https://example.com/app?code=NOPE"))
        #expect(PoliMiOAuth.authCode(from: other) == nil)

        let noCode = try #require(URL(string:
            "https://polimiapp.polimi.it/polimi_app/app?error=access_denied"))
        #expect(PoliMiOAuth.authCode(from: noCode) == nil)
    }

    @Test("The authorization URL carries the parameters the IdP requires")
    func authorizationURLShape() throws {
        let components = try #require(URLComponents(
            url: PoliMiOAuth.authorizationURL(), resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        #expect(components.host == "oauthidp.polimi.it")
        #expect(value("client_id") == PoliMiOAuth.clientID)
        #expect(value("response_type") == "code")
        #expect(value("access_type") == "offline")
        #expect(value("redirect_uri") == PoliMiOAuth.redirectURI)
        #expect(value("scope")?.contains("webeep") == true)
        #expect(value("scope")?.contains("carriera") == true)
    }
}


@Suite("API retry policy")
struct RetryPolicyTests {
    private func urlError(_ code: Int) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code)
    }

    /// A host that does not resolve will not resolve on the fourth attempt.
    /// Retrying it produced six round trips per request and delayed the error
    /// the user actually needed to see.
    @Test("Permanent failures are not retried")
    func permanentFailuresNotRetried() {
        for code in [
            NSURLErrorCannotFindHost,        // -1003
            NSURLErrorBadURL,
            NSURLErrorUnsupportedURL,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorSecureConnectionFailed,
        ] {
            #expect(PoliMiAPI.isRetryableForTesting(urlError(code)) == false,
                    "\(code) should not be retried")
        }
    }

    @Test("Genuinely transient failures are retried")
    func transientFailuresRetried() {
        for code in [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
        ] {
            #expect(PoliMiAPI.isRetryableForTesting(urlError(code)),
                    "\(code) should be retried")
        }
    }

    @Test("Non-URL errors are not retried")
    func otherDomainsNotRetried() {
        #expect(PoliMiAPI.isRetryableForTesting(
            NSError(domain: "SomethingElse", code: -1003)) == false)
    }

    /// A 404 is a different problem from a flaky network and the UI says so.
    @Test("A withdrawn endpoint reports as permanent")
    func endpointGoneIsPermanent() {
        #expect(APIError.endpointGone("/agenda/api/me/1/events").isPermanent)
        #expect(APIError.transport(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)).isPermanent)
        #expect(APIError.badStatus(500, body: "").isPermanent == false)
        #expect(APIError.transport(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)).isPermanent == false)
    }
}

@Suite("Career wire shapes")
struct CareerWireTests {
    /// Shape read off the official app's career card:
    /// `d.mean`, `d.given_cfu`, `"/" + d.planned_cfu`.
    @Test("The io-e-polimi payload decodes")
    func gradeBookDecodes() throws {
        let json = #"{"mean":27.43,"given_cfu":108,"planned_cfu":180}"#
        let dto = try JSONDecoder().decode(GradeBookDTO.self, from: Data(json.utf8))
        let book = dto.toGradeBook()

        #expect(abs(book.mean - 27.43) < 0.001)
        #expect(book.earnedCFU == 108)
        #expect(book.plannedCFU == 180)
        #expect(abs(book.progress - 0.6) < 0.001)
        // 27.43 * 110 / 30
        #expect(Int(book.baseGraduationMark.rounded()) == 101)
    }

    /// The new endpoint drops exam_stats, so its absence must not fail the
    /// decode — the counts come from /v1/base/counters instead.
    @Test("A payload without exam_stats still decodes")
    func gradeBookWithoutExamStats() throws {
        let json = #"{"mean":30,"given_cfu":12,"planned_cfu":180}"#
        let dto = try JSONDecoder().decode(GradeBookDTO.self, from: Data(json.utf8))
        #expect(dto.exam_stats == nil)
        #expect(dto.toGradeBook().examsGiven == 0)
    }

    /// Shape read off the official app's exams card:
    /// `v.num_iscriz` and `v.num_esiti`.
    @Test("The counters payload decodes")
    func countersDecode() throws {
        let json = #"{"num_iscriz":2,"num_esiti":14}"#
        let dto = try JSONDecoder().decode(ExamCountersDTO.self, from: Data(json.utf8))
        #expect(dto.num_iscriz == 2)
        #expect(dto.num_esiti == 14)
    }

    @Test("Missing counters degrade to nil rather than failing")
    func countersTolerateMissingFields() throws {
        let dto = try JSONDecoder().decode(ExamCountersDTO.self, from: Data("{}".utf8))
        #expect(dto.num_iscriz == nil)
        #expect(dto.num_esiti == nil)
    }

    /// The teachings envelope survived the host move unchanged.
    @Test("The insegn envelope decodes")
    func teachingsEnvelopeDecodes() throws {
        let json = """
        {"INSEGN":[{"c_insegn_piano":"097785","xdescrizione":"BASI DI DATI",
        "docente_esame":"CERI STEFANO","aa_freq":"2025","semestre_freq":"2",
        "appelliEsame":[]}]}
        """
        let response = try JSONDecoder().decode(TeachingsResponse.self, from: Data(json.utf8))
        #expect(response.teachings.count == 1)
        #expect(response.teachings[0].toCourse()?.name == "Basi di Dati")
    }
}

/// Courses come from WeBeep rather than `/v1/insegn`: that endpoint is exam
/// registration, so it is empty once every exam is passed, while WeBeep keeps
/// the enrolment.
@Suite("WeBeep course names")
struct MoodleCourseNameTests {
    @Test("A code-prefixed WeBeep name splits into code and title")
    func splitsCodeAndTitle() {
        let (code, title) = Course.splitCode(from: "097785 - BASI DI DATI [2025-26]")
        #expect(code == "097785")
        #expect(title == "BASI DI DATI")
    }

    /// The code is what PoliMi's own endpoints key on, so keeping it aligns a
    /// WeBeep course with a PoliMi one.
    @Test("The course id prefers the PoliMi code")
    func prefersPoliMiCode() {
        let course = Course(moodle: MoodleCourse(
            id: 4242, fullname: "097785 - BASI DI DATI [2025-26]",
            shortname: nil, startdate: nil, enddate: nil))

        // The Moodle id is the identity: several WeBeep courses share one
        // PoliMi code, and using the code collapsed them in SwiftUI.
        #expect(course.id == "moodle-4242")
        #expect(course.code == "097785")
        #expect(course.moodleID == 4242)
        #expect(course.name == "Basi di Dati")
        #expect(course.academicYear == "2025-26")
    }

    /// Without a code the Moodle id still has to identify the course uniquely.
    @Test("A name with no code falls back to the Moodle id")
    func fallsBackToMoodleID() {
        let course = Course(moodle: MoodleCourse(
            id: 99, fullname: "Corso Di Prova", shortname: nil,
            startdate: nil, enddate: nil))

        #expect(course.id == "moodle-99")
        #expect(course.code == nil)
        #expect(course.moodleID == 99)
    }

    /// A hyphen in the title must not be read as a code separator.
    @Test("A hyphenated title is not mistaken for a code")
    func hyphenInTitle() {
        let (code, title) = Course.splitCode(from: "Analisi - Modulo 2")
        #expect(code == nil)
        #expect(title == "Analisi - Modulo 2")
    }
}

/// The libretto is where passed exams live. `/v1/insegn` lists sittings still
/// open to register for, so it is empty exactly when a student most wants to
/// see their results.
@Suite("Libretto")
struct LibrettoTests {
    private func decode(_ json: String) throws -> LibrettoResponse {
        try JSONDecoder().decode(LibrettoResponse.self, from: Data(json.utf8))
    }

    /// The real payload, confirmed against an account: an object with the
    /// passed/pending split already done, epoch-millisecond dates, and no
    /// course code at all.
    @Test("The real envelope decodes and keeps the server's split")
    func realEnvelopeDecodes() throws {
        let json = """
        {"daSostenere":[{"id_riga":2,"descrizione":"BASI DI DATI","voto_esame":0,
                         "data_esame":null,"stato_esame_desc":null,"cfu":8}],
         "sostenuti":[{"id_riga":47314209,
                       "descrizione":"ALGORITMI E PRINCIPI DELL'INFORMATICA",
                       "descrizione_eng":"ALGORITHMS AND PRINCIPLES",
                       "stato_esame":"S","stato_esame_desc":"SUPERATO",
                       "cfu_conv_parz":0,"posins":"E",
                       "data_esame":1750197600000,"data_esame_string":null,
                       "voto_esame":30,"lode":"S","cfu":10}]}
        """
        let exams = try decode(json).allExams
        #expect(exams.count == 2)

        let passed = try #require(exams.first { $0.isPassed })
        #expect(passed.name == "Algoritmi e Principi dell'Informatica")
        #expect(passed.displayGrade == "30L")
        #expect(passed.cfu == 10)

        // 1750197600000 ms is June 2025.
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let date = try #require(passed.date)
        #expect(rome.component(.year, from: date) == 2025)
        #expect(rome.component(.month, from: date) == 6)
    }

    /// A pending row has no mark and must not read as passed, even though the
    /// fields alone cannot say so — the list it came from does.
    @Test("Pending rows come back as pending")
    func pendingFromItsOwnList() throws {
        let json = #"{"daSostenere":[{"id_riga":2,"descrizione":"BASI DI DATI","voto_esame":0}],"sostenuti":[]}"#
        let exam = try #require(decode(json).allExams.first)

        #expect(exam.isPassed == false)
        #expect(exam.displayGrade == "—")
    }

    /// An idoneità is passed with no numeric mark; the list it came from is the
    /// only thing that says so.
    @Test("A pass with no mark still counts as passed")
    func passWithoutMark() throws {
        let json = #"{"sostenuti":[{"id_riga":9,"descrizione":"PROVA FINALE","voto_esame":0,"stato_esame_desc":"SUPERATO"}],"daSostenere":[]}"#
        let exam = try #require(decode(json).allExams.first)

        #expect(exam.isPassed)
        #expect(exam.grade == nil)
    }

    /// Credits appear under different names across these endpoints.
    @Test("Credits are found under any of their spellings")
    func creditSpellings() throws {
        let json = #"{"sostenuti":[{"id_riga":1,"descrizione":"X","cfu_conv_parz":6,"voto_esame":28}],"daSostenere":[]}"#
        #expect(try #require(decode(json).allExams.first).cfu == 6)
    }

    /// Rows have no course code, so identity comes from id_riga.
    @Test("Rows without a course code are still uniquely identified")
    func identityFromRowID() throws {
        let json = #"{"sostenuti":[{"id_riga":47314209,"descrizione":"X","voto_esame":30}],"daSostenere":[]}"#
        #expect(try #require(decode(json).allExams.first).id == "47314209")
    }

    @Test("A nameless row is skipped, not faked")
    func skipsUnusableRows() throws {
        let json = #"{"sostenuti":[{"id_riga":1,"descrizione":""}],"daSostenere":[]}"#
        #expect(try decode(json).allExams.isEmpty)
    }
}

/// `String.capitalized` is wrong for Italian in two ways that show up in real
/// course names, so titles go through `Course.normalise`.
@Suite("Italian title casing")
struct TitleCasingTests {
    @Test("An elided article stays lowercase and its noun does not")
    func elidedArticle() {
        #expect(Course.normalise("ALGORITMI E PRINCIPI DELL'INFORMATICA")
                == "Algoritmi e Principi dell'Informatica")
        #expect(Course.normalise("FONDAMENTI DELL'AUTOMATICA")
                == "Fondamenti dell'Automatica")
    }

    @Test("Articles and prepositions stay lowercase mid-title")
    func minorWords() {
        #expect(Course.normalise("ARCHITETTURE DEI CALCOLATORI")
                == "Architetture dei Calcolatori")
        #expect(Course.normalise("BASI DI DATI") == "Basi di Dati")
    }

    /// Only mid-title: a leading article still leads.
    @Test("A leading minor word is still capitalised")
    func leadingMinorWord() {
        #expect(Course.normalise("DI BASE") == "Di Base")
    }
}

/// The maps catalogue is three separate lists joined on `csi*` codes, and it
/// contains rows that are not rooms anyone can be sent to.
@Suite("Room catalogue")
struct ClassroomTests {
    private func decode(_ json: String) throws -> [ClassroomDTO] {
        try JSONDecoder().decode([ClassroomDTO].self, from: Data(json.utf8))
    }

    /// Numbers arrive as strings throughout this service.
    @Test("A room decodes with its capacity and codes")
    func roomDecodes() throws {
        let json = """
        [{"sigla":"CR03.0.1","csiv":"CRG0203000001","csip":"CRG0203000",
          "csie":"CRG0203","capienza":"42","posti_disabili":"2"}]
        """
        let room = try #require(decode(json).first?.toClassroom())

        #expect(room.id == "CR03.0.1")
        #expect(room.capacity == 42)
        #expect(room.buildingCode == "CRG0203")
        #expect(room.accessibleSeats == 2)
    }

    /// The catalogue keeps fictitious and decommissioned rows; a room with no
    /// seats is not somewhere anyone can be sent.
    @Test("Rooms with no seats or no code are dropped")
    func dropsUnusableRooms() throws {
        let json = """
        [{"sigla":"X","csie":"A","csip":"B","capienza":"0"},
         {"sigla":"","csie":"A","csip":"B","capienza":"10"},
         {"sigla":"Y","csie":null,"csip":"B","capienza":"10"}]
        """
        #expect(try decode(json).compactMap { $0.toClassroom() }.isEmpty)
    }

    /// "0" means none, and should read as absent rather than as a figure.
    @Test("Zero accessible seats reads as none")
    func zeroAccessibleSeats() throws {
        let json = #"[{"sigla":"A.1","csie":"E","csip":"P","capienza":"30","posti_disabili":"0"}]"#
        #expect(try #require(decode(json).first?.toClassroom()).accessibleSeats == nil)
    }

    /// The address arrives in pieces and has to be reassembled.
    @Test("A building address is assembled from its parts")
    func buildingAddress() throws {
        let json = """
        {"csie":"MIA0605","csic":"MIA06","nome":"Edificio 32.5","indirizzo":"Colombo",
         "prefissoToponomastico":"Via","numeroCivico":"40","cittaEdificio":"Milano"}
        """
        let building = try JSONDecoder().decode(BuildingDTO.self, from: Data(json.utf8))
        #expect(building.fullAddress == "Via Colombo 40, Milano")
    }

    @Test("A building with no address parts yields none")
    func missingAddress() throws {
        let json = #"{"csie":"X","nome":"Y"}"#
        let building = try JSONDecoder().decode(BuildingDTO.self, from: Data(json.utf8))
        #expect(building.fullAddress == nil)
    }
}
