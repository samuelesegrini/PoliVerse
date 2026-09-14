import Foundation

/// New posts in a course's announcements forum.
///
/// Like ``MaterialChangeDetector`` — silent first reading, an old snapshot is
/// a new baseline — with posts in place of files. A post is new when it was
/// created after the last reading and not seen before; an edited or replied-to
/// post is not news. An empty forum is a real answer early in a term, so it
/// still counts as a reading.
nonisolated enum AnnouncementDetector {
    struct Result: Sendable {
        let updates: [ExamUpdate]
        let snapshot: MaterialSnapshot
    }

    /// The forums a teacher posts announcements in, by instance id.
    ///
    /// Moodle creates one per course ("Annunci", "Announcements", "Avvisi",
    /// "News forum"); open discussion forums are left alone.
    static func forumInstances(in sections: [MoodleSection]) -> [Int] {
        sections.flatMap { $0.modules ?? [] }.compactMap { module in
            guard module.modname == "forum", let instance = module.instance else { return nil }
            let name = DocumentClassifier.normalise(module.name)
            let isAnnouncements = name.range(
                of: #"\b(annunci|avvisi|announcements?|news forum)\b"#, options: .regularExpression) != nil
            return isAnnouncements ? instance : nil
        }
    }

    /// Posts created this long before the last reading still count as new:
    /// the server's clock and a refresh in flight are not exact.
    static let clockMargin: TimeInterval = 600
    /// Post ids remembered per forum.
    static let remembered = 50

    static func detect(
        previous: MaterialSnapshot?, posts: [MoodleDiscussion], course: MaterialCourse,
        context: MaterialContext, now: Date
    ) -> Result {
        guard let previous, now.timeIntervalSince(previous.takenAt) < MaterialChangeDetector.staleAfter else {
            var baseline = MaterialSnapshot(versions: [:], notable: [:], takenAt: now)
            for post in posts { baseline.versions[key(post)] = String(post.created ?? 0) }
            return Result(updates: [], snapshot: baseline)
        }

        // Merged, not replaced: Moodle orders by pinned, then by last
        // activity, so a reply or an edit brings an old post back into the
        // few returned — it must not read as new.
        var snapshot = previous
        snapshot.takenAt = now
        for post in posts { snapshot.versions[key(post)] = String(post.created ?? 0) }
        if snapshot.versions.count > remembered {
            let newest = snapshot.versions.sorted { (Int($0.value) ?? 0) > (Int($1.value) ?? 0) }.prefix(remembered)
            snapshot.versions = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }

        let since = previous.takenAt.addingTimeInterval(-clockMargin)
        let updates = posts
            .filter { post in
                guard previous.versions[key(post)] == nil, let created = post.created else { return false }
                // Created after the last reading: new. Older and unseen only
                // because it slipped into the few returned: not news.
                return Date(timeIntervalSince1970: TimeInterval(created)) >= since
            }
            .map { post in
                // §11.2: tied to a sitting — and so worth a push — only when
                // it talks about exams and names that sitting's date.
                let sitting = [context.next, context.lastSat].compactMap { $0 }
                    .first { isAboutExams(post) && mentions($0, in: post) }
                return ExamUpdate(
                    kind: .announcementPosted, examID: nil, courseCode: course.code,
                    courseName: course.name, detectedAt: now, source: .webeep,
                    evidence: "webeep:mod_forum_get_forum_discussions course=\(course.moodleID) discussion=\(post.discussion ?? post.id)",
                    newValue: post.title, identity: key(post),
                    wasEnrolled: sitting != nil, examDate: sitting)
            }
        return Result(updates: updates, snapshot: snapshot)
    }

    /// Whether a post talks about exams — sittings, enrolment, marks — rather
    /// than lectures. Read from the subject and the message as plain text.
    /// Deliberately narrow: "aula", "spostata" and "scritto" describe lessons
    /// just as often.
    static func isAboutExams(_ post: MoodleDiscussion) -> Bool {
        let text = DocumentClassifier.normalise(post.title + " " + HTMLText.plain(post.message ?? ""))
        return text.range(of: examWords, options: .regularExpression) != nil
    }

    /// Italian and English, since English-taught courses announce in English.
    private static let examWords = #"\b(esam[ei]|appell[oi]|iscrizion[ei]|esit[oi]|vot[oi]|risultati|oral[ei]|compitin[oi]|itinere|verbalizzazion[ei]|exams?|midterms?|grades|results|orals?|registration|resits?|retakes?)\b"#

    private static let months = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio",
                                 "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    private static let englishMonths = ["january", "february", "march", "april", "may", "june", "july",
                                        "august", "september", "october", "november", "december"]

    /// Whether a post names a sitting's day: "12/02", "12.2.2026", "12 febbraio",
    /// "12 February", "February 12th".
    static func mentions(_ date: Date, in post: MoodleDiscussion) -> Bool {
        let calendar = PoliMiDate.romeCalendar
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let text = DocumentClassifier.normalise(post.title + " " + HTMLText.plain(post.message ?? ""))
        // `normalise` turns dots and dashes into spaces: "12.02" is "12 02".
        let numeric = #"(?<!\d)0?\#(day)[ /]0?\#(month)(?!\d)"#
        let written = #"(?<!\d)0?\#(day) \#(months[month - 1])\b"#
        // "may" and "march" are verbs too: "exercise 3 may be skipped" is not
        // the third of May. Those two need a clearer date around them.
        let english = englishMonths[month - 1]
        let verbLike = english == "may" || english == "march"
        let dayFirst = verbLike
            ? #"(?<!\d)0?\#(day)(st|nd|rd|th)? (of )?\#(english)(?! (be|not|have|also|to|on|in)\b)\b"#
            : #"(?<!\d)0?\#(day)(st|nd|rd|th)? (of )?\#(english)\b"#
        let monthFirst = #"\b\#(english) 0?\#(day)(st|nd|rd|th)?(?!\d)"#
        return [numeric, written, dayFirst, monthFirst].contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func key(_ post: MoodleDiscussion) -> String { "post:\(post.discussion ?? post.id)" }
}
