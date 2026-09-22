import Foundation

/// Notices new posts in a course's announcements forum.
///
/// Reads like ``MaterialChangeDetector``, with posts in place of files: the first
/// reading is silent and a stale snapshot becomes a new baseline. A post counts as
/// new when it was created after the last reading and has not been seen before, so an
/// edited or replied-to post — which Moodle brings back to the top of the list — is
/// not news. An empty forum is a real answer early in a term and still counts as a
/// reading.
///
/// A post is tied to a sitting, and so becomes worth pushing, only when it talks about
/// exams and names that sitting's date.
nonisolated enum AnnouncementDetector {
    /// What one reading produced.
    struct Result: Sendable {
        /// The posts that are new since the previous reading.
        let updates: [ExamUpdate]
        /// The reading to compare the next one against.
        let snapshot: MaterialSnapshot
    }

    /// The forums a lecturer posts announcements in.
    ///
    /// Open discussion forums are left alone.
    ///
    /// - Parameter sections: The course's contents.
    /// - Returns: The announcement forums' instance ids.
    static func forumInstances(in sections: [MoodleSection]) -> [Int] {
        CourseForum.forums(in: sections).filter { $0.kind == .announcements }.map(\.id)
    }

    /// How far before the last reading a post may have been created and still count as
    /// new. The server's clock and a refresh in flight are not exact.
    static let clockMargin: TimeInterval = 600
    /// How many post ids are remembered per forum.
    static let remembered = 50

    /// Compares a forum's posts against the previous reading.
    ///
    /// The snapshot is merged rather than replaced, because Moodle orders by pinned and
    /// then by last activity, so an old post brought back by a reply must not read as new.
    /// The oldest ids are dropped once more than ``remembered`` are held.
    ///
    /// - Parameters:
    ///   - previous: The last reading, or `nil` for the first.
    ///   - posts: The discussions Moodle answered.
    ///   - course: The course being read.
    ///   - context: The course's next and last sittings, for tying a post to one.
    ///   - now: The moment of this reading.
    /// - Returns: The new posts and the reading to compare against next.
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

    /// Whether a post talks about exams — sittings, enrolment, marks — rather than
    /// lectures.
    ///
    /// Read from the subject and the body as plain text, and deliberately narrow: words
    /// like “aula”, “spostata” and “scritto” describe lessons just as often.
    ///
    /// - Parameter post: The post to judge.
    /// - Returns: `true` when it names something exam-related.
    static func isAboutExams(_ post: MoodleDiscussion) -> Bool {
        let text = DocumentClassifier.normalise(post.title + " " + HTMLText.plain(post.message ?? ""))
        return text.range(of: examWords, options: .regularExpression) != nil
    }

    /// Wordings that name something exam-related, in Italian and English.
    private static let examWords = #"\b(esam[ei]|appell[oi]|iscrizion[ei]|esit[oi]|vot[oi]|risultati|oral[ei]|compitin[oi]|itinere|verbalizzazion[ei]|exams?|midterms?|grades|results|orals?|registration|resits?|retakes?)\b"#

    /// Italian month names, indexed from January.
    private static let months = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio",
                                 "agosto", "settembre", "ottobre", "novembre", "dicembre"]
    /// English month names, indexed from January.
    private static let englishMonths = ["january", "february", "march", "april", "may", "june", "july",
                                        "august", "september", "october", "november", "december"]

    /// Whether a post names a given day.
    ///
    /// Matches `12/02`, `12.2.2026`, `12 febbraio`, `12 February` and `February 12th`.
    /// “May” and “March” are also English verbs, so those two require a clearer date
    /// around them.
    ///
    /// - Parameters:
    ///   - date: The day to look for.
    ///   - post: The post to search, subject and body.
    /// - Returns: `true` when any form matches.
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

    /// The snapshot key for one post, by discussion id where there is one.
    ///
    /// - Parameter post: The post.
    /// - Returns: The key.
    private static func key(_ post: MoodleDiscussion) -> String { "post:\(post.discussion ?? post.id)" }
}
