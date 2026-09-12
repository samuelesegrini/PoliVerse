import Foundation
import Testing
@testable import PoliVerse

/// Local changes that the Politecnico has not accepted yet.
///
/// The bug: tapping a star offline flipped an in-memory flag and queued the
/// change, but `Course.isFavourite` is deliberately not persisted — it is
/// reapplied from WeBeep on load — so a relaunch showed the star **off** while
/// the queue still intended to turn it on. The app contradicted itself, and
/// `isHidden` behaved differently again because that one *is* encoded.
@Suite("Optimistic flags")
struct OptimisticFlagsTests {
    private func flags() -> OptimisticFlags {
        OptimisticFlags(defaults: UserDefaults(
            suiteName: "optimistic-\(UUID().uuidString)")!)
    }

    private func course(_ id: String, moodleID: Int? = 1,
                        favourite: Bool = false, hidden: Bool = false) -> Course {
        Course(id: id, name: id, teacher: "—", cfu: 0, semester: "—",
               academicYear: "2025/26", moodleID: moodleID,
               isFavourite: favourite, isHidden: hidden)
    }

    @Test("An override survives being written and read back")
    func persists() {
        let defaults = UserDefaults(suiteName: "optimistic-\(UUID().uuidString)")!
        var flags = OptimisticFlags(defaults: defaults)
        flags.set(favourite: true, for: "moodle-1")

        let reopened = OptimisticFlags(defaults: defaults)
        #expect(reopened.favourite(for: "moodle-1") == true)
    }

    /// The heart of it: an unsent change wins over what the server last said,
    /// because it is newer and the user made it.
    @Test("An override beats the server's value")
    func overridesServer() {
        var flags = flags()
        flags.set(favourite: true, for: "moodle-1")
        let applied = flags.apply(to: [course("moodle-1", favourite: false)])
        #expect(applied[0].isFavourite)
    }

    /// And it applies to WeBeep courses, which is exactly where the old code
    /// gave up: it only consulted local state for courses WeBeep did not know.
    @Test("Overrides apply to WeBeep courses too")
    func appliesToMoodleCourses() {
        var flags = flags()
        flags.set(hidden: true, for: "moodle-7")
        let applied = flags.apply(to: [course("moodle-7", moodleID: 7)])
        #expect(applied[0].isHidden)
    }

    /// Once the change reaches the Politecnico the server is the truth again,
    /// or an old override would resurrect a favourite removed on the web.
    @Test("Clearing an override returns to the server's value")
    func clearing() {
        var flags = flags()
        flags.set(favourite: true, for: "moodle-1")
        flags.clear(favouriteFor: "moodle-1")
        let applied = flags.apply(to: [course("moodle-1", favourite: false)])
        #expect(!applied[0].isFavourite)
        #expect(flags.favourite(for: "moodle-1") == nil)
    }

    @Test("Favourite and hidden are tracked apart")
    func independent() {
        var flags = flags()
        flags.set(favourite: true, for: "c")
        flags.set(hidden: true, for: "c")
        flags.clear(favouriteFor: "c")
        #expect(flags.favourite(for: "c") == nil)
        #expect(flags.hidden(for: "c") == true)
    }

    /// Turning something off is a change too, and false must not read as
    /// "nothing recorded".
    @Test("An override of false is an override, not an absence")
    func falseIsAValue() {
        var flags = flags()
        flags.set(favourite: false, for: "c")
        #expect(flags.favourite(for: "c") == false)
        let applied = flags.apply(to: [course("c", favourite: true)])
        #expect(!applied[0].isFavourite)
    }

    @Test("Courses with no override are untouched")
    func untouched() {
        let flags = flags()
        let applied = flags.apply(to: [course("c", favourite: true, hidden: true)])
        #expect(applied[0].isFavourite)
        #expect(applied[0].isHidden)
    }
}

/// The round trip the override exists for: tap offline, relaunch, deliver.
@Suite("Optimistic lifecycle")
struct OptimisticLifecycleTests {
    private func course(_ id: String, moodleID: Int, favourite: Bool = false) -> Course {
        Course(id: id, name: id, teacher: "—", cfu: 0, semester: "—",
               academicYear: "2025/26", moodleID: moodleID, isFavourite: favourite)
    }

    /// The bug, end to end. WeBeep says the course is not a favourite; the
    /// user starred it offline; a relaunch rebuilds the list from the cache
    /// and the server, and must still show the star on.
    @Test("An unsent star survives the list being rebuilt")
    func survivesRebuild() {
        let defaults = UserDefaults(suiteName: "lifecycle-\(UUID().uuidString)")!
        var flags = OptimisticFlags(defaults: defaults)
        flags.set(favourite: true, for: "moodle-9")

        // A fresh launch: new flags object, server's value is still false.
        let reloaded = OptimisticFlags(defaults: defaults)
        let rebuilt = reloaded.apply(to: [course("moodle-9", moodleID: 9)])
        #expect(rebuilt[0].isFavourite)
    }

    /// And once it is delivered the server is authoritative again, or a
    /// favourite removed later from the web would be resurrected on every
    /// load, forever.
    @Test("Once delivered, the server wins again")
    func deliveredReleasesControl() {
        let defaults = UserDefaults(suiteName: "lifecycle-\(UUID().uuidString)")!
        var flags = OptimisticFlags(defaults: defaults)
        flags.set(favourite: true, for: "moodle-9")
        flags.clear(favouriteFor: "moodle-9")

        let rebuilt = OptimisticFlags(defaults: defaults)
            .apply(to: [course("moodle-9", moodleID: 9, favourite: false)])
        #expect(!rebuilt[0].isFavourite)
    }

    /// Un-starring offline is the same mechanism in reverse, and the one a
    /// naive "only store what is on" design gets wrong.
    @Test("An unsent un-star also survives")
    func survivesUnstar() {
        let defaults = UserDefaults(suiteName: "lifecycle-\(UUID().uuidString)")!
        var flags = OptimisticFlags(defaults: defaults)
        flags.set(favourite: false, for: "moodle-9")

        let rebuilt = OptimisticFlags(defaults: defaults)
            .apply(to: [course("moodle-9", moodleID: 9, favourite: true)])
        #expect(!rebuilt[0].isFavourite)
    }
}
