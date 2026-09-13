import Foundation
import Testing
@testable import PoliVerse

/// New posts in a course's announcements forum.
///
/// The forum is where a teacher writes "the exam moves to room L.26", and it
/// is otherwise only visible by opening the course or reading every email.
@Suite("Announcement detector")
struct AnnouncementDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)
    private let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")

    /// Created a minute after `now`, so after the baseline taken at `now`.
    private func post(_ id: Int, _ subject: String, message: String = "<p>Testo</p>",
                      created: Int? = nil) -> MoodleDiscussion {
        let created = created ?? Int(now.timeIntervalSince1970) + 60
        return MoodleDiscussion(id: id, discussion: id, name: subject, subject: subject, message: message,
                                created: created, timemodified: created, userfullname: "Stefano Ceri", pinned: false)
    }

    private var later: Date { now.addingTimeInterval(3600) }

    private func detect(_ previous: MaterialSnapshot?, _ posts: [MoodleDiscussion],
                        context: MaterialContext = .none, at time: Date? = nil) -> AnnouncementDetector.Result {
        AnnouncementDetector.detect(previous: previous, posts: posts, course: course,
                                    context: context, now: time ?? now)
    }

    @Test("The announcements forum is found among a course's modules")
    func findForum() {
        let sections = [MoodleSection(id: 1, name: "Generale", modules: [
            MoodleModule(id: 1, name: "Forum di discussione", modname: "forum", contents: nil, instance: 11),
            MoodleModule(id: 2, name: "Annunci", modname: "forum", contents: nil, instance: 12),
            MoodleModule(id: 3, name: "Lezione 1", modname: "resource", contents: nil, instance: 13),
        ])]
        #expect(AnnouncementDetector.forumInstances(in: sections) == [12])
        let english = [MoodleSection(id: 1, name: "General", modules: [
            MoodleModule(id: 4, name: "Announcements", modname: "forum", contents: nil, instance: 21),
        ])]
        #expect(AnnouncementDetector.forumInstances(in: english) == [21])
    }

    @Test("The first reading is a silent baseline; a new post is news")
    func newPost() {
        let base = detect(nil, [post(1, "Benvenuti")])
        #expect(base.updates.isEmpty)
        let result = detect(base.snapshot, [post(2, "Aule per l'appello del 12 febbraio"), post(1, "Benvenuti")], at: later)
        #expect(result.updates.map(\.kind) == [.announcementPosted])
        #expect(result.updates.first?.newValue == "Aule per l'appello del 12 febbraio")
        #expect(result.updates.first?.source == .webeep)
    }

    /// Teachers fix typos. An edited post is not a second announcement.
    @Test("An edited post says nothing; an empty forum is still a reading")
    func quiet() {
        let base = detect(nil, [post(1, "Benvenuti")])
        #expect(detect(base.snapshot, [post(1, "Benvenuti!")], at: later).updates.isEmpty)
        let empty = detect(base.snapshot, [], at: later)
        #expect(empty.updates.isEmpty)
        #expect(empty.snapshot.versions == base.snapshot.versions)
        #expect(empty.snapshot.takenAt == later)
    }

    /// Moodle lists pinned posts first and orders the rest by last activity:
    /// a reply brings an old, never-seen post into the page.
    @Test("An old post surfacing in the page is not news")
    func oldPostSurfaces() {
        let base = detect(nil, [post(1, "Benvenuti")])
        let old = post(9, "Programma del corso", created: Int(now.timeIntervalSince1970) - 30 * 86400)
        #expect(detect(base.snapshot, [old, post(1, "Benvenuti")], at: later).updates.isEmpty)
    }

    @Test("A post seen once is not announced again when it leaves and returns")
    func returns() {
        let base = detect(nil, [post(1, "Benvenuti")])
        let first = detect(base.snapshot, [post(2, "Esame spostato"), post(1, "Benvenuti")], at: later)
        #expect(first.updates.count == 1)
        let gone = detect(first.snapshot, [post(1, "Benvenuti")], at: later.addingTimeInterval(3600))
        let back = detect(gone.snapshot, [post(2, "Esame spostato")], at: later.addingTimeInterval(7200))
        #expect(back.updates.isEmpty)
    }

    @Test("An old snapshot is a new baseline")
    func stale() {
        let base = detect(nil, [post(1, "Benvenuti")])
        let stale = now.addingTimeInterval(MaterialChangeDetector.staleAfter + 60)
        #expect(detect(base.snapshot, [post(2, "Esame spostato"), post(1, "Benvenuti")], at: stale).updates.isEmpty)
    }

    /// §11.2: Alta only when it names the student's sitting — exam words
    /// and that sitting's date (here 2 March).
    @Test("A post is tied to a sitting only when it talks about exams and names its date", arguments: [
        ("Aule per l'appello del 2 marzo", "<p>Trovate la suddivisione allegata.</p>", true),
        ("Avviso", "<p>L'orale del 02/03 è <b>rinviato</b>.</p>", true),
        ("Esiti della prova in itinere", "", false),
        ("Lezione del 2 marzo", "<p>La lezione è spostata in aula B.3.2.</p>", false),
    ])
    func examRelated(_ subject: String, _ message: String, _ related: Bool) {
        let base = detect(nil, [post(1, "Benvenuti")])
        let next = now.addingTimeInterval(5 * 86400)
        let update = detect(base.snapshot, [post(2, subject, message: message), post(1, "Benvenuti")],
                            context: MaterialContext(lastSat: nil, next: next), at: later).updates.first
        #expect(update?.wasEnrolled == related)
        #expect(update?.examDate == (related ? next : nil))
    }
}
