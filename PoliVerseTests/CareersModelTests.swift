import Foundation
import Testing
@testable import PoliVerse

/// Which enrolment the app is pointed at.
///
/// Not a display detail: nearly every PoliMi endpoint is parameterised by the
/// matricola, and the token is bound to one enrolment. Point the app at a
/// closed career and `iae` answers "Utente non abilitato Code: 6" for
/// everything — which is how the whole problem was found, and which nothing
/// tested until this model stopped requiring a ``Session``.
@Suite("Careers")
@MainActor
struct CareersModelTests {
    private static let listPath = "/v1/careers/list"

    private static func list(_ rows: [(String, String)]) -> Data {
        let json = rows.map { #"{"matricola": "\#($0.0)", "stato": "\#($0.1)"}"# }
        return Data("[\(json.joined(separator: ","))]".utf8)
    }

    /// Defaults of their own, so one test cannot inherit another's choice —
    /// which is the exact bug the per-person key exists to prevent.
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "careers-\(UUID().uuidString)")!
    }

    private func model(_ http: FixtureHTTP, matricola: String? = "111",
                       personCode: String? = "p1",
                       defaults: UserDefaults? = nil) -> CareersModel {
        CareersModel(account: StubAccount(matricola: matricola, personCode: personCode,
                                          http: http),
                     defaults: defaults ?? self.defaults())
    }

    @Test("The list is read and the one in use is recognised")
    func readsTheList() async {
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Attiva"), ("222", "Chiusa")])])
        let careers = model(http)

        await careers.load()

        #expect(careers.careers.count == 2)
        #expect(careers.current?.matricola == "111")
        #expect(careers.hasChoice)
    }

    /// A switcher is not worth showing for a single enrolment.
    @Test("One enrolment offers no choice and suggests no switch")
    func singleCareerIsNoChoice() async {
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Attiva")])])
        let careers = model(http)

        await careers.load()

        #expect(careers.hasChoice == false)
        #expect(careers.suggestedSwitch() == nil)
    }

    /// The active career is the one whose exam services will answer, so being
    /// on the closed one is what the suggestion exists to correct.
    @Test("Sitting on a closed career suggests the active one")
    func suggestsTheActiveCareer() async throws {
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Chiusa"), ("222", "Attiva")])])
        // Signed in on the closed enrolment.
        let careers = model(http, matricola: "111")

        await careers.load()

        #expect(try #require(careers.suggestedSwitch()).matricola == "222")
    }

    @Test("Already on the active career, nothing is suggested")
    func nothingToSuggest() async {
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Chiusa"), ("222", "Attiva")])])
        let careers = model(http, matricola: "222")

        await careers.load()

        #expect(careers.suggestedSwitch() == nil)
    }

    /// Switching re-runs OAuth and takes the student through a web view, so
    /// the app must not keep offering a switch they have declined.
    @Test("A remembered choice is not offered again")
    func rememberedChoiceIsNotReoffered() async throws {
        let defaults = defaults()
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Chiusa"), ("222", "Attiva")])])
        let careers = model(http, matricola: "111", defaults: defaults)
        await careers.load()

        // The student chose to stay where they are.
        let staying = try #require(careers.careers.first { $0.matricola == "111" })
        careers.remember(staying)

        #expect(careers.suggestedSwitch() == nil)
    }

    /// Two accounts on one device must not inherit each other's choice, which
    /// is why the key is the person code and not the matricola.
    @Test("A choice is remembered per person, not per device")
    func choiceIsPerPerson() async throws {
        let defaults = defaults()
        let rows = Self.list([("111", "Chiusa"), ("222", "Attiva")])

        let mine = model(FixtureHTTP([Self.listPath: rows]), matricola: "111",
                         personCode: "p1", defaults: defaults)
        await mine.load()
        mine.remember(try #require(mine.careers.first { $0.matricola == "111" }))
        #expect(mine.suggestedSwitch() == nil)

        // Another person, same device: they have chosen nothing.
        let theirs = model(FixtureHTTP([Self.listPath: rows]), matricola: "111",
                           personCode: "p2", defaults: defaults)
        await theirs.load()
        #expect(theirs.suggestedSwitch()?.matricola == "222")
    }

    @Test("A failed list is reported and leaves no careers")
    func failureIsReported() async {
        let careers = model(FixtureHTTP.failing(APIError.badStatus(500, body: "down")))

        await careers.load()

        #expect(careers.careers.isEmpty)
        #expect(careers.errorMessage != nil)
    }

    /// Best effort: the local choice is what the app acts on, and a failure
    /// here changes nothing the student can see.
    @Test("Telling the Politecnico the favourite is a PUT that may fail quietly")
    func favouriteIsBestEffort() async throws {
        let http = FixtureHTTP([Self.listPath: Self.list([("111", "Attiva")])],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let careers = model(http)
        await careers.load()

        await careers.markFavourite(try #require(careers.careers.first))

        let put = try #require(await http.requests.first { $0.method == "PUT" })
        #expect(put.path == "/v1/careers/favorite/111")
        // Nothing surfaced: the list still reads normally.
        #expect(careers.careers.count == 1)
    }

    @Test("Sample data is served without touching the network")
    func sampleBranch() async {
        let http = FixtureHTTP()
        let careers = CareersModel(
            account: StubAccount(isSample: true, http: http), defaults: defaults())

        await careers.load()

        #expect(!careers.careers.isEmpty)
        #expect(await http.requests.isEmpty)
    }
}
