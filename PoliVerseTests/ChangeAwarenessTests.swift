import Foundation
import Testing
@testable import PoliVerse

/// Change awareness: what a refresh changed in a stored copy, found by the
/// identity of the items, and the marks that point it out until the student has
/// seen it. The detector is checked alone, then through the real ``Loader``,
/// ``Query`` and ``OfflineStore`` with a resource whose answers the test sets.
/// Test names carry the id of the requirement they check (docs/rasd).
@Suite("Novità di un aggiornamento")
@MainActor
struct ChangeAwarenessTests {
    private nonisolated struct Boom: Error {}

    private nonisolated struct Row: Identifiable, Equatable, Codable, Sendable {
        let id: Int
        var text: String
    }

    private nonisolated struct Board: Equatable, Codable, Sendable {
        var left: [Row] = []
        var right: [Row] = []
    }

    private nonisolated enum Side: String, Hashable, Sendable, CaseIterable { case left, right }

    /// What the server answers, as the test wrote it. A side set to `nil` fails.
    private actor Desk {
        private var rows: [Side: [Row]] = [:]
        private(set) var fetches = 0

        func set(_ side: Side, _ answer: [Row]?) { rows[side] = answer }
        func answer(_ side: Side) -> [Row]? { rows[side] }
        func noteFetch() { fetches += 1 }
    }

    /// Two lists, each a part, compared row by row.
    private nonisolated struct Boards: Resource {
        typealias Part = Side
        static let id = "boards"
        static let ttl: TimeInterval = 900
        let desk: Desk

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: Board?) async throws -> Board {
            try await fetch(key, env: env, parts: Set(Side.allCases), over: previous, progress: LoadProgress()).value
        }

        @concurrent
        func fetch(_ key: Whole, env: Env, parts: Set<Side>, over held: Board?,
                   progress: LoadProgress<Boards>) async throws -> LoadProgress<Boards>.Snapshot {
            await desk.noteFetch()
            var board = held ?? Board()
            var arrived: Set<Side> = []
            var failed: Set<Side> = []
            for side in Side.allCases where parts.contains(side) {
                guard let rows = await desk.answer(side) else {
                    failed.insert(side)
                    continue
                }
                if side == .left { board.left = rows } else { board.right = rows }
                arrived.insert(side)
                progress.report(board, arrived: arrived, failed: failed)
            }
            guard !arrived.isEmpty else { throw Boom() }
            return .init(value: board, arrived: arrived, failed: failed)
        }

        func changes(in part: Side, from old: Board, to new: Board) -> ChangeSet {
            switch part {
            case .left: ChangeDetector.changes(from: old.left, to: new.left)
            case .right: ChangeDetector.changes(from: old.right, to: new.right)
            }
        }
    }

    private static let env = Env(http: FixtureHTTP(), matricola: "111", isSample: false)

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("changes-\(UUID().uuidString)", isDirectory: true)
    }

    private func rows(_ texts: [Int: String]) -> [Row] {
        texts.sorted { $0.key < $1.key }.map { Row(id: $0.key, text: $0.value) }
    }

    // MARK: - R26: the detector

    @Test("R26: aggiunti, cambiati e tolti si riconoscono dall’identità")
    func test_R26_addedChangedRemovedByIdentity() {
        let old = rows([1: "a", 2: "b", 3: "c"])
        let new = rows([2: "b", 3: "C", 4: "d"])
        let changes = ChangeDetector.changes(from: old, to: new)
        #expect(changes.added == ["4"])
        #expect(changes.changed == ["3"])
        #expect(changes.removed == ["1"])
        #expect(changes.marked == ["3", "4"])
        #expect(!changes.isEmpty)
    }

    @Test("R26: la stessa risposta non cambia niente, in qualsiasi ordine")
    func test_R26_sameItemsInAnotherOrderAreNoChange() {
        let old = rows([1: "a", 2: "b"])
        #expect(ChangeDetector.changes(from: old, to: old.reversed()).isEmpty)
    }

    @Test("R26: il primo sguardo e una risposta vuota non si confrontano")
    func test_R26_firstLookAndEmptyAnswerAreNotCompared() {
        let some = rows([1: "a", 2: "b"])
        // A copy with nothing in it: everything would be "new".
        #expect(ChangeDetector.changes(from: [Row](), to: some).isEmpty)
        // The services answer empty between sessions: not forty withdrawals.
        #expect(ChangeDetector.changes(from: some, to: [Row]()).isEmpty)
    }

    @Test("R26: due elementi con la stessa identità contano una volta")
    func test_R26_duplicateIdentitiesCountOnce() {
        let old = [Row(id: 1, text: "a"), Row(id: 1, text: "z")]
        let new = [Row(id: 1, text: "a"), Row(id: 1, text: "y"), Row(id: 2, text: "b")]
        let changes = ChangeDetector.changes(from: old, to: new)
        #expect(changes.changed.isEmpty)
        #expect(changes.added == ["2"])
    }

    // MARK: - R26: in the loader

    @Test("R26: la prima risposta non è un cambiamento, la seconda dice che cosa è cambiato")
    func test_R26_refreshOverAHeldCopySaysWhatChanged() async throws {
        let desk = Desk()
        await desk.set(.left, rows([1: "a", 2: "b"]))
        await desk.set(.right, rows([7: "x"]))
        let loader = Loader(Boards(desk: desk), offline: OfflineStore(directory: folder()))

        let first = try await loader.value(Whole(), env: Self.env)
        #expect(first.changes.isEmpty)

        await desk.set(.left, rows([1: "a", 2: "B", 3: "c"]))
        let second = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(second.changes[.left] == ChangeSet(added: ["3"], changed: ["2"]))
        // The other part answered the same.
        #expect(second.changes[.right] == ChangeSet())

        // A refresh that finds nothing replaces what the one before found.
        let third = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(third.changes[.left] == ChangeSet())
    }

    @Test("R26: la copia rimessa dal disco è confrontata come quella in memoria")
    func test_R26_restoredCopyIsCompared() async throws {
        let folder = folder()
        let desk = Desk()
        await desk.set(.left, rows([1: "a"]))
        await desk.set(.right, rows([7: "x"]))
        let store = OfflineStore(directory: folder)
        _ = try await Loader(Boards(desk: desk), offline: store).value(Whole(), env: Self.env)
        await store.flushed()

        // The app is started again, and the server has something more.
        await desk.set(.left, rows([1: "a", 2: "b"]))
        let again = Loader(Boards(desk: desk), offline: OfflineStore(directory: folder))
        let restored = await again.restore(Whole(), env: Self.env)
        #expect(restored?.changes.isEmpty == true)
        let fetched = try await again.value(Whole(), env: Self.env, force: true)
        #expect(fetched.changes[.left]?.added == ["2"])
    }

    @Test("R26: una parte che non aveva mai risposto non ha niente con cui confrontarsi")
    func test_R26_partThatNeverAnsweredIsNotCompared() async throws {
        let desk = Desk()
        await desk.set(.left, rows([1: "a"]))
        await desk.set(.right, nil)
        let loader = Loader(Boards(desk: desk), offline: OfflineStore(directory: folder()))
        _ = try await loader.value(Whole(), env: Self.env)

        // The right side answers for the first time, over a value that exists.
        await desk.set(.right, rows([7: "x", 8: "y"]))
        let second = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(second.changes[.right] == nil)
        #expect(second.value.right.count == 2)
    }

    @Test("R26: una parte fallita non dice che tutto è stato tolto")
    func test_R26_failedPartChangesNothing() async throws {
        let desk = Desk()
        await desk.set(.left, rows([1: "a"]))
        await desk.set(.right, rows([7: "x"]))
        let loader = Loader(Boards(desk: desk), offline: OfflineStore(directory: folder()))
        _ = try await loader.value(Whole(), env: Self.env)

        await desk.set(.right, nil)
        let second = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(second.failed == [.right])
        #expect(second.changes[.right] == nil)
        #expect(second.value.right == rows([7: "x"]))
    }

    // MARK: - R28: on the query

    @Test("R28: la Query dice una volta sola che cosa ha cambiato un aggiornamento")
    func test_R28_queryTellsOnceWhatARefreshChanged() async throws {
        let desk = Desk()
        await desk.set(.left, rows([1: "a"]))
        await desk.set(.right, rows([7: "x"]))
        let query = Query(Boards(desk: desk), account: StubAccount(matricola: "111"),
                          offline: OfflineStore(directory: folder()))
        var told: [(Side, ChangeSet)] = []
        query.onChanges = { told.append(($0, $1)) }

        await query.load()
        #expect(told.isEmpty)
        #expect(query.changes(of: .left).isEmpty)

        await desk.set(.left, rows([1: "A", 2: "b"]))
        await query.load(force: true)
        #expect(told.count == 1)
        #expect(told.first?.0 == .left)
        #expect(told.first?.1.marked == ["1", "2"])
        #expect(query.changes(of: .left).marked == ["1", "2"])
        #expect(query.changes(of: .right).isEmpty)

        // Opening the screen again asks nothing and says nothing again.
        let fetches = await desk.fetches
        await query.load()
        #expect(await desk.fetches == fetches)
        #expect(told.count == 1)
    }

    // MARK: - R26: the career

    private func sitting(_ id: Int, room: String? = nil, enrolledCount: Int? = nil,
                         status: ExamStatus = .open) -> ExamSession {
        ExamSession(id: id, courseName: "Fisica", courseCode: "F1", teacher: nil,
                    date: Date(timeIntervalSince1970: 1_800_000_000), room: room,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: enrolledCount,
                    kind: nil, status: status, hasCorrections: false)
    }

    private func result(_ id: String, grade: Int?) -> LibrettoExam {
        LibrettoExam(id: id, name: "Fisica", grade: grade, hasLode: false, cfu: 8, date: nil,
                     statusText: nil, isPassed: grade != nil)
    }

    @Test("R26: negli appelli conta ciò che lo studente deve sapere, non il numero di iscritti")
    func test_R26_careerComparesWhatMattersInASitting() {
        let source = CareerSource()
        let old = CareerSource.Payload(sessions: [sitting(1, enrolledCount: 10), sitting(2), sitting(3)])

        // More students enrolled, and the student's own enrolment: not news.
        let busier = CareerSource.Payload(sessions: [sitting(1, enrolledCount: 40), sitting(2, status: .enrolled), sitting(3)])
        #expect(source.changes(in: .sittings, from: old, to: busier).isEmpty)

        // A room published, a mark published, a sitting added.
        let grade = ExamStatus.graded(ExamGrade(value: 27, text: "27", passed: true, refusable: true))
        let news = CareerSource.Payload(sessions: [sitting(1, room: "B.2.1"), sitting(2, status: grade),
                                                   sitting(3), sitting(4)])
        let changes = source.changes(in: .sittings, from: old, to: news)
        #expect(changes.changed == ["1", "2"])
        #expect(changes.added == ["4"])
    }

    @Test("R26: nel libretto conta l’esito; le cifre della carriera non si confrontano")
    func test_R26_careerComparesResultsInTheLibretto() {
        let source = CareerSource()
        let old = CareerSource.Payload(libretto: [result("A", grade: nil), result("B", grade: 28)])
        let new = CareerSource.Payload(gradeBook: .sample, libretto: [result("A", grade: 30), result("B", grade: 28)])
        #expect(source.changes(in: .libretto, from: old, to: new).changed == ["A"])
        #expect(source.changes(in: .book, from: old, to: new).isEmpty)
    }

    // MARK: - R27: the marks

    @Test("R27: un elemento resta segnato finché la sua sezione non è stata vista")
    func test_R27_markedUntilTheSectionIsSeen() {
        let marks = NewMarks(offline: OfflineStore(directory: folder()))
        marks.show(account: "111")
        marks.mark(["3", "4"], in: "appelli", account: "111")
        marks.mark(["A"], in: "libretto", account: "111")

        #expect(marks.isNew("3", in: "appelli"))
        #expect(marks.justMarked("3", in: "appelli"))
        #expect(!marks.isNew("3", in: "libretto"))
        #expect(!marks.isNew("9", in: "appelli"))

        marks.seen("appelli")
        #expect(!marks.isNew("3", in: "appelli"))
        #expect(!marks.justMarked("3", in: "appelli"))
        // Seeing one section says nothing about the other.
        #expect(marks.isNew("A", in: "libretto"))
    }

    @Test("R27: una sezione sfiorata non è stata vista")
    func test_R27_aGlanceIsNotSeeing() {
        #expect(!NewMarks.wasSeen(shownFor: .milliseconds(300)))
        #expect(NewMarks.wasSeen(shownFor: NewMarks.glance))
        #expect(NewMarks.wasSeen(shownFor: .seconds(20)))
    }

    @Test("R27: i segni sopravvivono alla chiusura dell’app, e sono dell’account")
    func test_R27_marksSurviveARelaunchAndBelongToTheAccount() async {
        let folder = folder()
        let store = OfflineStore(directory: folder)
        let marks = NewMarks(offline: store)
        marks.show(account: "111")
        marks.mark(["3"], in: "appelli", account: "111")
        // A load that outlived a career switch: stored for its account, shown to nobody.
        marks.mark(["8"], in: "appelli", account: "222")
        #expect(!marks.isNew("8", in: "appelli"))
        await store.flushed()

        let relaunched = NewMarks(offline: OfflineStore(directory: folder))
        relaunched.show(account: "111")
        #expect(relaunched.isNew("3", in: "appelli"))
        #expect(!relaunched.isNew("8", in: "appelli"))
        // Marked in an earlier run: drawn at once, not written in again.
        #expect(!relaunched.justMarked("3", in: "appelli"))

        relaunched.show(account: "222")
        #expect(relaunched.isNew("8", in: "appelli"))
        #expect(!relaunched.isNew("3", in: "appelli"))
    }

    @Test("R40: all’uscita non resta nessun segno, né a schermo né sul telefono")
    func test_R40_marksGoAtSignOut() async {
        let folder = folder()
        let store = OfflineStore(directory: folder)
        let marks = NewMarks(offline: store)
        marks.show(account: "111")
        marks.mark(["3"], in: "appelli", account: "111")
        await store.flushed()

        // What signing out does.
        marks.forget()
        store.clear(account: "111")
        await store.flushed()
        #expect(!marks.isNew("3", in: "appelli"))

        let next = NewMarks(offline: OfflineStore(directory: folder))
        next.show(account: "111")
        #expect(!next.isNew("3", in: "appelli"))
    }

    // MARK: - R26, R27: the career, end to end

    private static func insegn(_ sittings: [Int]) -> Data {
        let rows = sittings.map { "{\"c_insegn_piano\": \"A\($0)\", \"xdescrizione\": \"Corso \($0)\", \"appelliEsame\": [{\"c_appello\": \($0)}]}" }
        return Data("{\"INSEGN\": [\(rows.joined(separator: ","))]}".utf8)
    }

    @Test("R26, R27: un appello comparso tra due aperture dell’app è segnato come nuovo, gli altri no")
    func test_R26_R27_careerMarksASittingThatAppeared() async {
        let folder = folder()
        let store = OfflineStore(directory: folder)
        let firstMarks = NewMarks(offline: store)
        let first = CareerModel(
            account: StubAccount(matricola: "111", http: FixtureHTTP(
                ["/v1/insegn": Self.insegn([1, 2])], fallback: .failure(APIError.badStatus(500, body: "down")))),
            feed: UpdateFeed(offline: store), offline: store, marks: firstMarks)
        await first.load()
        #expect(first.sessions.count == 2)
        // The first look is a baseline: nothing is new.
        #expect(firstMarks.marked.isEmpty)
        await store.flushed()

        // The app is started again; a third sitting has been published.
        let again = OfflineStore(directory: folder)
        let marks = NewMarks(offline: again)
        let second = CareerModel(
            account: StubAccount(matricola: "111", http: FixtureHTTP(
                ["/v1/insegn": Self.insegn([1, 2, 3])], fallback: .failure(APIError.badStatus(500, body: "down")))),
            feed: UpdateFeed(offline: again), offline: again, marks: marks)
        await second.load(force: true)

        #expect(second.sessions.count == 3)
        #expect(marks.isNew("3", in: CareerModel.sittingsSection))
        #expect(!marks.isNew("1", in: CareerModel.sittingsSection))
        #expect(!marks.isNew("2", in: CareerModel.sittingsSection))
        #expect(marks.marked[CareerModel.librettoSection] == nil)
    }
}
