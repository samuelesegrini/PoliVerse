import Foundation

/// What a WeBeep item is about, as far as its names say.
nonisolated enum DocumentTag: String, Sendable, Codable, CaseIterable {
    /// `results` for a list of marks, `solutions` for worked answers, `examText` for the
    /// paper itself, and `examNotice` for rooms, lists or instructions. These four are
    /// the tags that can raise a notification.
    case results, solutions, examText, examNotice
    /// `exercise` for practice material, `lectureMaterial` for slides and notes,
    /// `assignment` for work to hand in, `recording` for video, and `admin` for the
    /// syllabus, rules and calendar.
    case exercise, lectureMaterial, assignment, recording, admin
}

/// Tags a WeBeep item from its file name, its module name and its section.
///
/// Rules rather than a model: every tag traces to a word, and the tags that can raise
/// a notification are the ones with the fewest ways to be spelled. Every rule reads
/// both Italian and English, since a teaching's language varies by module and degree
/// course.
///
/// A tag is a strong hint, never a fact: it is what lets the app say that a file of
/// results was posted rather than that a mark is out.
///
/// The rule table and its rationale are in `docs/academic-intelligence-layer.md`
/// §9.2.
nonisolated enum DocumentClassifier {
    /// Tags one item.
    ///
    /// The file and module names say what the item is; the section name says only what
    /// the items around it are, so it can add ``DocumentTag/examNotice`` but can never
    /// turn a lecture into results. ``DocumentTag/examText`` is suppressed when the item
    /// is already solutions, and ``DocumentTag/results`` when the wording is a syllabus's
    /// learning outcomes.
    ///
    /// - Parameters:
    ///   - fileName: The file's name.
    ///   - moduleName: The module's name on the course page.
    ///   - sectionName: The section's name.
    ///   - modname: Moodle's module kind; `assign` implies ``DocumentTag/assignment``.
    ///   - mimetype: The file's media type; a video implies ``DocumentTag/recording``.
    /// - Returns: The tags, possibly empty.
    static func tags(
        fileName: String, moduleName: String, sectionName: String,
        modname: String, mimetype: String?
    ) -> Set<DocumentTag> {
        var tags: Set<DocumentTag> = []

        if modname == "assign" { tags.insert(.assignment) }
        if mimetype?.hasPrefix("video/") == true { tags.insert(.recording) }

        // The file and module say what this item is; the section only says
        // what the items around it are, so it can add a notice but never
        // turn a lecture into results.
        let own = normalise("\(fileName) \(moduleName)")
        let section = normalise(sectionName)

        if matches(results, own), !matches(learningOutcomes, own) { tags.insert(.results) }
        if matches(solutions, own) { tags.insert(.solutions) }
        if matches(examText, own), !tags.contains(.solutions) { tags.insert(.examText) }
        if matches(notice, own) || matches(notice, section) { tags.insert(.examNotice) }
        if matches(exercise, own) { tags.insert(.exercise) }
        if matches(lecture, own) { tags.insert(.lectureMaterial) }
        if matches(admin, own) { tags.insert(.admin) }

        return tags
    }

    // Every rule reads Italian and English: a teaching's language is per
    // module and per degree course (see `TeachingLanguage`), and teachers of
    // English-taught courses name their files in English.
    // R1 — results. "ammessi" covers "ammessi all'orale"; "z scores" is
    // statistics, not marks.
    /// Wordings that name a list of marks.
    private static let results = #"\b(esit[oi]|risultati|valutazioni|vot[oi]|graduatoria|ammessi|results|grades|marks|(?<!z )scores|admitted)\b"#
    /// Wordings a syllabus uses for its learning outcomes, which would otherwise read as
    /// results.
    private static let learningOutcomes = #"(risultati (di apprendimento|attesi)|learning outcomes)"#
    // R2 — solutions.
    /// Wordings that name worked answers.
    private static let solutions = #"\b(soluzion[ei]|svolt[oaie]|correzion[ei]|solutions?|solved|risolt[oiae]|answer keys?|answers)\b"#
    // R3 — the text of an exam.
    /// Wordings that name the exam paper itself.
    private static let examText = #"\b(testo|tema|traccia|compito|exam papers?|exam texts?|past exams?)\b"#
    // R4 — notices: rooms, lists, instructions.
    /// Wordings that name a notice about rooms, lists or instructions.
    private static let notice = #"\b(aule?|suddivisione|ripartizione|convocazion[ei]|istruzioni|avvis[oi]|orari[oa]? (dell )?esame|rooms?|room allocation|seating|instructions|notices?|exam schedule)\b"#
    // R6, R7, R10.
    /// Wordings that name practice material.
    private static let exercise = #"\b(esercitazion[ei]|eserciz[io]|exercises?|tutorato|lab|laboratorio|tutorials?|problem sets?|practice sessions?)\b"#
    /// Wordings that name lecture material.
    private static let lecture = #"\b(lezion[ei]|lectures?|slides?|lucidi|dispens[ae]|capitolo|handouts?|lecture notes)\b"#
    /// Wordings that name the syllabus, the rules or the calendar.
    private static let admin = #"\b(programma|syllabus|regole|modalita d esame|calendario|exam rules|course schedule)\b"#

    /// Whether normalised text matches a pattern.
    ///
    /// The patterns are held as strings rather than `Regex` literals, which are not
    /// `Sendable` and these are shared by every call.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern.
    ///   - text: Text already passed through ``normalise(_:)``.
    /// - Returns: `true` on a match.
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Reduces a name to the words a person would read: lower-cased, accents folded, and
    /// separators turned into spaces — so `Esiti_31-08.PDF` becomes `esiti 31 08 pdf` and
    /// word boundaries fall where they should.
    ///
    /// - Parameter text: The name as written.
    /// - Returns: The normalised text.
    static func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it"))
            .lowercased()
            .replacingOccurrences(of: #"[_\-.'’]+"#, with: " ", options: .regularExpression)
    }
}
