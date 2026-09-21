import Foundation
import Testing
@testable import PoliVerse

/// The course list, which before ``Store`` could not be constructed in a test
/// at all: it took the whole ``WeBeepModel``, which takes a ``Session``, which
/// takes the Keychain.
@Suite("Course list")
@MainActor
struct CourseModelTests {
    /// Stands in for WeBeep. Three methods, because that is the whole of what
    /// the course list asks of it — see ``CourseEnrolments``.
    private final class StubEnrolments: CourseEnrolments {
        var enrolled: [Course] = []
        /// What the next flag write should answer. False is the offline case,
        /// which is the branch the queue exists for.
        var accepts = true
        private(set) var favouriteWrites: [(Int, Bool)] = []
        private(set) var hiddenWrites: [(Int, Bool)] = []

        func enrolledCourses() async -> [Course] { enrolled }

        func setFavourite(_ favourite: Bool, moodleID: Int) async -> Bool {
            favouriteWrites.append((moodleID, favourite))
            return accepts
        }

        func setHidden(_ hidden: Bool, moodleID: Int) async -> Bool {
            hiddenWrites.append((moodleID, hidden))
            return accepts
        }
    }

    /// Defaults of their own, so a test cannot see another's flags or the
    /// developer's.
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "courses-\(UUID().uuidString)")!
    }

    private static func insegn(_ names: [String]) -> Data {
        let rows = names.enumerated().map { index, name in
            "{\"c_insegn_piano\": \"\(index + 1)\", \"xdescrizione\": \"\(name)\", \"aa_freq\": \"2025\"}"
        }
        return Data("{\"INSEGN\": [\(rows.joined(separator: ","))]}".utf8)
    }

    /// A WeBeep-shaped course. Built here rather than from ``Course/samples``
    /// so a test states exactly the two facts it depends on: the moodle id
    /// (which decides who owns the flags) and the name (which decides sorting).
    private static func course(id: String, name: String, moodleID: Int?) -> Course {
        Course(id: id, name: name, teacher: "—", cfu: 0, semester: "1",
               academicYear: "2025", moodleID: moodleID)
    }

    // MARK: - Which service answers

    /// The distinction the source's doc comment exists for: `/v1/insegn` is the
    /// exam-registration endpoint, so a student who has passed everything gets
    /// an empty array from it. WeBeep keeps enrolments after the exam is
    /// passed, so it has to lead.
    @Test("WeBeep answers when it has courses, and iae is never asked")
    func weBeepLeads() async throws {
        let enrolments = StubEnrolments()
        enrolments.enrolled = [Self.course(id: "wb1", name: "Analisi", moodleID: 7)]
        let http = FixtureHTTP(["/v1/insegn": Self.insegn(["Fisica"])])
        let model = CourseModel(account: StubAccount(http: http), enrolments: enrolments, defaults: defaults())

        await model.load()

        #expect(model.courses.map(\.name) == ["Analisi"])
        #expect(await http.requests.isEmpty)
    }

    @Test("iae answers when WeBeep has nothing")
    func iaeFallback() async throws {
        let enrolments = StubEnrolments()
        let http = FixtureHTTP(["/v1/insegn": Self.insegn(["Fisica"])])
        let model = CourseModel(account: StubAccount(http: http), enrolments: enrolments, defaults: defaults())

        await model.load()

        #expect(model.courses.map(\.name) == ["Fisica"])
        let request = try #require(await http.requests.first)
        #expect(request.host == .iae)
        #expect(request.path == "/v1/insegn")
    }

    // MARK: - Flags

    /// The bug ``OptimisticFlags`` was written for: a star tapped offline
    /// flipped an in-memory flag and queued the change, but the list came back
    /// unstarred while the queue still intended to turn it on.
    @Test("A favourite that WeBeep refused stays on and is queued")
    func offlineFavouriteSticks() async throws {
        let enrolments = StubEnrolments()
        enrolments.enrolled = [Self.course(id: "wb1", name: "Analisi", moodleID: 7)]
        enrolments.accepts = false
        let model = CourseModel(account: StubAccount(http: FixtureHTTP()),
                                enrolments: enrolments, defaults: defaults())
        await model.load()

        let course = try #require(model.courses.first)
        #expect(course.isFavourite == false)
        model.toggleFavourite(course)

        // Immediately, before the write has been attempted: the tap shows.
        #expect(model.courses.first?.isFavourite == true)

        // And it survives the refetch, which returns it unstarred.
        await model.load(force: true)
        #expect(model.courses.first?.isFavourite == true)
    }

    /// Dropping the override is the point: keeping it would make the app ignore
    /// a favourite removed later from the web, forever.
    @Test("A delivered change hands ownership back to the server")
    func deliveredChangeDropsOverride() async throws {
        let enrolments = StubEnrolments()
        enrolments.enrolled = [Self.course(id: "wb1", name: "Analisi", moodleID: 7)]
        enrolments.accepts = false
        let model = CourseModel(account: StubAccount(http: FixtureHTTP()),
                                enrolments: enrolments, defaults: defaults())
        await model.load()
        model.toggleFavourite(try #require(model.courses.first))
        #expect(model.courses.first?.isFavourite == true)

        model.confirmDelivered(.courseFavourite(moodleID: 7, value: true))
        await model.load(force: true)

        // The server said unstarred and there is no longer an override, so the
        // server wins again.
        #expect(model.courses.first?.isFavourite == false)
    }

    @Test("Favourites sort above everything else")
    func favouritesSortFirst() async throws {
        let enrolments = StubEnrolments()
        enrolments.enrolled = [
            Self.course(id: "a", name: "Analisi", moodleID: 1),
            Self.course(id: "z", name: "Zoologia", moodleID: 2),
        ]
        enrolments.accepts = false
        let model = CourseModel(account: StubAccount(http: FixtureHTTP()),
                                enrolments: enrolments, defaults: defaults())
        await model.load()

        let zoologia = try #require(model.courses.first { $0.name == "Zoologia" })
        model.toggleFavourite(zoologia)

        #expect(model.courses.map(\.name) == ["Zoologia", "Analisi"])
    }

    @Test("Hiding a course takes it out of the visible list")
    func hiddenLeavesTheList() async throws {
        let enrolments = StubEnrolments()
        enrolments.enrolled = [Self.course(id: "wb1", name: "Analisi", moodleID: 7)]
        enrolments.accepts = false
        let model = CourseModel(account: StubAccount(http: FixtureHTTP()),
                                enrolments: enrolments, defaults: defaults())
        await model.load()

        model.toggleHidden(try #require(model.courses.first))

        #expect(model.visibleCourses.isEmpty)
        #expect(model.hiddenOnly.count == 1)
    }
}
