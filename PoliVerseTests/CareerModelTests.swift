import Foundation
import Testing
@testable import PoliVerse

/// The career screen, whose load was the app's most complicated and least
/// tested: six endpoints across three hosts, each allowed to fail on its own,
/// with rules about which combinations mean "nothing to show" and which mean
/// "this account is not entitled".
///
/// None of that was reachable before — the model took a ``Session``, so the
/// six-way partial-failure logic had no test of any kind.
@Suite("Career")
@MainActor
struct CareerModelTests {
    private static let matricola = "111"
    private static let gradeBookPath = "/v1/io-e-polimi/111"
    private static let librettoPath = "/elencoinsegnamenti/111"

    private func offline() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("career-\(UUID().uuidString)", isDirectory: true))
    }

    private func model(_ http: FixtureHTTP, offline: OfflineStore? = nil) -> CareerModel {
        CareerModel(account: StubAccount(matricola: Self.matricola, http: http),
                    feed: UpdateFeed(), offline: offline ?? self.offline())
    }

    private static func gradeBook(mean: Double, cfu: Int) -> Data {
        Data("{\"mean\": \(mean), \"given_cfu\": \(cfu), \"planned_cfu\": 180}".utf8)
    }

    private static func counters(subscribed: Int, given: Int) -> Data {
        Data("{\"num_iscriz\": \(subscribed), \"num_esiti\": \(given)}".utf8)
    }

    /// Two sittings of two different teachings, so the derived "planned" count
    /// is 2 rather than the number of rows.
    private static let insegn = Data("""
    {"INSEGN": [
      {"c_insegn_piano": "A1", "xdescrizione": "Analisi", "appelliEsame": [{"c_appello": 1}]},
      {"c_insegn_piano": "B2", "xdescrizione": "Fisica", "appelliEsame": [{"c_appello": 2}]}
    ]}
    """.utf8)

    // MARK: - Partial failure

    /// The rule the whole fetch turns on: both load-bearing calls empty means
    /// there is nothing to show, and what was already on screen must stay.
    @Test("With neither the gradebook nor the sittings, nothing is claimed")
    func nothingLoaded() async {
        let career = model(FixtureHTTP.failing(APIError.badStatus(500, body: "down")))

        await career.load()

        #expect(career.gradeBook == GradeBook.empty)
        #expect(career.errorMessage != nil)
    }

    /// The other half of the same rule: one of the two is enough.
    @Test("The gradebook alone is enough to show a career")
    func gradeBookAlone() async {
        let http = FixtureHTTP([Self.gradeBookPath: Self.gradeBook(mean: 27.5, cfu: 60)],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let career = model(http)

        await career.load()

        #expect(career.gradeBook.mean == 27.5)
        #expect(career.gradeBook.earnedCFU == 60)
        #expect(career.errorMessage == nil)
    }

    /// A failed load must not replace a student's exam record with a blank
    /// screen — the bug that made losing signal look like losing a degree.
    @Test("A later failure keeps the record that was already loaded")
    func failureKeepsRecord() async {
        let account = StubAccount(
            matricola: Self.matricola,
            http: FixtureHTTP([Self.gradeBookPath: Self.gradeBook(mean: 27.5, cfu: 60)],
                              fallback: .failure(APIError.badStatus(500, body: "down"))))
        let career = CareerModel(account: account, feed: UpdateFeed(), offline: offline())
        await career.load()

        account.http = FixtureHTTP.failing(APIError.badStatus(500, body: "down"))
        await career.load(force: true)

        #expect(career.gradeBook.mean == 27.5)
        #expect(career.errorMessage != nil)
    }

    // MARK: - How the counts are assembled

    /// The gradebook endpoint no longer carries exam counts; they come from
    /// the IAE counters call, and merging the two is the fetch's job.
    @Test("Exam counts come from the counters call, not the gradebook")
    func countsComeFromCounters() async {
        let http = FixtureHTTP([
            Self.gradeBookPath: Self.gradeBook(mean: 27, cfu: 60),
            "/v1/base/counters": Self.counters(subscribed: 3, given: 9),
        ], fallback: .failure(APIError.badStatus(500, body: "down")))
        let career = model(http)

        await career.load()

        #expect(career.gradeBook.examsSubscribed == 3)
        #expect(career.gradeBook.examsGiven == 9)
    }

    /// `/v1/insegn` knows the whole plan, so the planned count survives the
    /// counters call being down.
    @Test("The planned count is derived from the sittings when counters fail")
    func plannedDerivedFromSittings() async {
        let http = FixtureHTTP(["/v1/insegn": Self.insegn],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let career = model(http)

        await career.load()

        // Two distinct teachings, not two rows.
        #expect(career.gradeBook.examsPlanned == 2)
    }

    // MARK: - Entitlement

    /// "This account may not use this service" is permanent for this user, so
    /// retrying is pointless and it must not be shown as a failure they could
    /// retry. The session is fine; a subset of services is not.
    @Test("A refused profile is reported as its own state, not as an error")
    func refusedProfile() async {
        let http = FixtureHTTP([Self.gradeBookPath: Self.gradeBook(mean: 27, cfu: 60)],
                               fallback: .failure(APIError.notEntitled("iae", body: "Utente non abilitato")))
        let career = model(http)

        await career.load()

        #expect(career.examServicesRefused)
        #expect(career.errorMessage == nil)
    }

    // MARK: - Offline

    /// A student on a train should still see their exam record — and, now that
    /// sittings are cached too, when their next exam is.
    @Test("The record and the sittings survive a cold start with no network")
    func offlineRecord() async {
        let offline = offline()
        let first = model(FixtureHTTP([
            Self.gradeBookPath: Self.gradeBook(mean: 27.5, cfu: 60),
            "/v1/insegn": Self.insegn,
        ], fallback: .failure(APIError.badStatus(500, body: "down"))), offline: offline)
        await first.load()
        offline.flush()

        // A fresh model, as after a relaunch, with nothing reachable.
        let second = model(FixtureHTTP.failing(APIError.transport(URLError(.notConnectedToInternet))),
                           offline: offline)
        await second.load()

        #expect(second.gradeBook.mean == 27.5)
        #expect(second.sessions.count == 2)
        #expect(second.age != nil)
    }

    /// The token is bound to one matricola, so reading another career's plan
    /// out of its cache is the only way to show it without switching.
    @Test("Another career's libretto is readable from its cache")
    func cachedLibrettoForAnotherCareer() async {
        let offline = offline()
        offline.save(CareerSource.Payload(libretto: LibrettoExam.samples()),
                     as: CareerSource.id, account: "999")
        offline.flush()

        let other = CareerModel.cachedLibretto(account: "999", store: offline)

        #expect(other?.isEmpty == false)
    }

    // MARK: - Target average

    /// The figure the student chose is theirs; losing it because a tunnel
    /// arrived first would be rude.
    @Test("A target that could not be saved is kept and queued")
    func targetSurvivesAFailedSave() async {
        let career = model(FixtureHTTP.failing(APIError.badStatus(500, body: "down")))

        let saved = await career.saveTarget(28.5)

        #expect(saved == false)
        #expect(career.officialTarget == 28.5)
    }

    @Test("A saved target is sent as a PUT to the libretto host")
    func targetIsSaved() async throws {
        let http = FixtureHTTP(["/mediaobiettivo/insertmediaobiettivo": Data("{}".utf8)])
        let career = model(http)

        let saved = await career.saveTarget(28.5)

        #expect(saved)
        let request = try #require(await http.requests.first)
        #expect(request.method == "PUT")
        #expect(request.host == .libretto)
        #expect(career.officialTarget == 28.5)
    }
}
