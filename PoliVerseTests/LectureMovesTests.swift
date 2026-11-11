import Foundation
import Testing
@testable import PoliVerse

/// A lecture moved to another room or time: found by comparing the stored week
/// with the fetched one, recorded in the feed, and delivered within the limits
/// that already apply to exam news. Test names carry the id of the requirement
/// they check (docs/rasd).
@MainActor
@Suite("Lezioni spostate")
struct LectureMovesTests {
    /// 2026-02-25 10:00 in Rome: outside quiet hours whenever the suite runs.
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func lecture(_ id: Int, inHours hours: Double = 24, room: String? = "5.1.1",
                         kind: EventKind = .lecture, title: String = "Fisica") -> AgendaEvent {
        let start = now.addingTimeInterval(hours * 3600)
        return AgendaEvent(id: id, title: title, start: start, end: start.addingTimeInterval(7200),
                           kind: kind, roomAcronym: room)
    }

    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("lectures-\(UUID().uuidString)", isDirectory: true))
    }

    // MARK: - Finding a move

    @Test("R29: una lezione che cambia aula o orario è una lezione spostata")
    func test_R29_roomOrTimeChangedIsAMove() {
        let old = [lecture(1), lecture(2, inHours: 48), lecture(3, inHours: 72)]
        let new = [lecture(1, room: "3.0.2"), lecture(2, inHours: 50), lecture(3, inHours: 72)]
        let moves = LectureMoves.moves(from: old, to: new, now: now)

        #expect(moves.map(\.id) == [1, 2])
        #expect(moves[0].oldRoom == "5.1.1")
        #expect(moves[0].newRoom == "3.0.2")
        #expect(!moves[0].timeChanged)
        #expect(moves[1].timeChanged)
    }

    @Test("R29: la stessa settimana non sposta niente, e ciò che non è una lezione non conta")
    func test_R29_sameWeekAndOtherEntriesAreNotMoves() {
        let week = [lecture(1), lecture(2, inHours: 48)]
        #expect(LectureMoves.moves(from: week, to: week, now: now).isEmpty)

        // A deadline whose time changed is the deadlines' business.
        let old = [lecture(1), lecture(9, kind: .deadline)]
        let new = [lecture(1), lecture(9, inHours: 30, kind: .deadline)]
        #expect(LectureMoves.moves(from: old, to: new, now: now).isEmpty)

        // Only the title or the notes changed: the appointment is the same.
        #expect(LectureMoves.moves(from: [lecture(1)], to: [lecture(1, title: "Fisica I")], now: now).isEmpty)
    }

    @Test("R29: una lezione già cominciata, una tolta e una aggiunta non sono spostamenti")
    func test_R29_pastRemovedAndAddedAreNotMoves() {
        // Its room was corrected after the fact.
        #expect(LectureMoves.moves(from: [lecture(1, inHours: -3), lecture(2)],
                                   to: [lecture(1, inHours: -3, room: "3.0.2"), lecture(2)], now: now).isEmpty)
        // One gone and another there: nothing says they are the same lecture.
        #expect(LectureMoves.moves(from: [lecture(1), lecture(2)], to: [lecture(1), lecture(3)], now: now).isEmpty)
    }

    @Test("R29: il primo sguardo e una settimana tornata vuota non spostano niente")
    func test_R29_firstLookAndEmptyAnswerAreNotMoves() {
        #expect(LectureMoves.moves(from: [], to: [lecture(1)], now: now).isEmpty)
        #expect(LectureMoves.moves(from: [lecture(1)], to: [], now: now).isEmpty)
    }

    // MARK: - What the student is told

    @Test("R29: l’aggiornamento dice da dove a dove, e ogni spostamento è una notizia sua")
    func test_R29_updateSaysFromWhereToWhere() {
        let move = LectureMoves.moves(from: [lecture(1)], to: [lecture(1, room: "3.0.2")], now: now)[0]
        let update = LectureMoves.update(for: move, now: now)

        #expect(update.kind == .lectureMoved)
        #expect(update.kind.category == .lectures)
        #expect(update.source == .agenda)
        #expect(update.courseName == "Fisica")
        #expect(update.oldValue == "5.1.1")
        #expect(update.newValue == "3.0.2")
        #expect(update.examDate == move.newStart)

        // Moved again, to a third room: not the same sighting.
        let again = LectureMoves.moves(from: [lecture(1, room: "3.0.2")], to: [lecture(1, room: "B.2.1")], now: now)[0]
        #expect(LectureMoves.update(for: again, now: now).id != update.id)
    }

    @Test("R29: entro la settimana è una notifica nel limite giornaliero, più in là va nel riepilogo")
    func test_R29_deliveredWithinTheDailyLimit() {
        func update(_ id: Int, inHours hours: Double, title: String) -> ExamUpdate {
            let move = LectureMoves.moves(from: [lecture(id, inHours: hours, title: title)],
                                          to: [lecture(id, inHours: hours, room: "3.0.2", title: title)], now: now)[0]
            return LectureMoves.update(for: move, now: now)
        }
        func decide(_ updates: [ExamUpdate], _ preferences: NotificationPreferences = NotificationPreferences()) -> [ExamUpdate.Delivery] {
            ExamUpdatePolicy.decide(updates, history: [], preferences: preferences, now: now).map(\.delivery)
        }

        #expect(decide([update(1, inHours: 24, title: "Fisica")]) == [.push])
        #expect(decide([update(1, inHours: 24 * 20, title: "Fisica")]) == [.digest])

        // The fourth ordinary push of the day waits for the summary, as for exam news.
        let four = ["Fisica", "Analisi", "Chimica", "Algebra"].enumerated().map {
            update($0.offset + 1, inHours: 24, title: $0.element)
        }
        #expect(decide(four) == [.push, .push, .push, .digest])

        // Switched off by the student: in the app only.
        var off = NotificationPreferences()
        off.setCategory(.lectures, enabled: false)
        #expect(decide([update(1, inHours: 24, title: "Fisica")], off) == [.inApp])
    }

    // MARK: - Through the feed

    @Test("R29: lo spostamento entra nel feed una volta sola e viene consegnato")
    func test_R29_feedRecordsAMoveOnce() async {
        final class Delivered { var kinds: [ExamUpdate.Kind] = [] }
        let delivered = Delivered()
        let offline = store()
        let feed = UpdateFeed(offline: offline, clock: { [now] in now },
                              onNewUpdates: { delivered.kinds += $0.map(\.kind) })
        feed.show(account: "111")
        let moves = LectureMoves.moves(from: [lecture(1)], to: [lecture(1, room: "3.0.2")], now: now)

        await feed.recordLectures(moves, account: "111")
        // A foreground load and a background refresh seeing the same move.
        await feed.recordLectures(moves, account: "111")
        await feed.recordLectures([], account: "111")

        #expect(delivered.kinds == [.lectureMoved])
        #expect(feed.updates.map(\.kind) == [.lectureMoved])
        #expect(feed.updates.first?.title == "Lezione spostata")

        let reopened = UpdateFeed(offline: offline, clock: { [now] in now })
        reopened.show(account: "111")
        #expect(reopened.updates.map(\.kind) == [.lectureMoved])
    }

    @Test("R29: lo spostamento di un altro account non compare a chi è sullo schermo")
    func test_R29_anotherAccountsMoveIsNotShown() async {
        final class Delivered { var count = 0 }
        let delivered = Delivered()
        let feed = UpdateFeed(offline: store(), clock: { [now] in now },
                              onNewUpdates: { delivered.count += $0.count })
        feed.show(account: "111")
        let moves = LectureMoves.moves(from: [lecture(1)], to: [lecture(1, room: "3.0.2")], now: now)

        await feed.recordLectures(moves, account: "222")
        #expect(feed.updates.isEmpty)
        #expect(delivered.count == 0)
    }
}
