import Foundation

/// What a WeBeep item is about, as far as its names say.
nonisolated enum DocumentTag: String, Sendable, Codable, CaseIterable {
    case results, solutions, examText, examNotice
    case exercise, lectureMaterial, assignment, recording, admin
}

/// Tags a WeBeep item from its file name, its module name and its section.
///
/// Rules, not a model: every tag can be traced to a word, and the ones that
/// can trigger a notification — results, solutions, notices — are the ones
/// with the fewest ways to be spelled. Rule table and rationale in
/// `docs/academic-intelligence-layer.md` §9.2.
///
/// A tag here is a strong hint, never a fact: it is what makes the app say
/// "a file of results was posted", not "your grade is out".
nonisolated enum DocumentClassifier {
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
    private static let results = #"\b(esit[oi]|risultati|valutazioni|vot[oi]|graduatoria|ammessi|results|grades|marks|(?<!z )scores|admitted)\b"#
    /// Syllabi call their learning outcomes "risultati di apprendimento".
    private static let learningOutcomes = #"(risultati (di apprendimento|attesi)|learning outcomes)"#
    // R2 — solutions.
    private static let solutions = #"\b(soluzion[ei]|svolt[oaie]|correzion[ei]|solutions?|solved|risolt[oiae]|answer keys?|answers)\b"#
    // R3 — the text of an exam.
    private static let examText = #"\b(testo|tema|traccia|compito|exam papers?|exam texts?|past exams?)\b"#
    // R4 — notices: rooms, lists, instructions.
    private static let notice = #"\b(aule?|suddivisione|ripartizione|convocazion[ei]|istruzioni|avvis[oi]|orari[oa]? (dell )?esame|rooms?|room allocation|seating|instructions|notices?|exam schedule)\b"#
    // R6, R7, R10.
    private static let exercise = #"\b(esercitazion[ei]|eserciz[io]|exercises?|tutorato|lab|laboratorio|tutorials?|problem sets?|practice sessions?)\b"#
    private static let lecture = #"\b(lezion[ei]|lectures?|slides?|lucidi|dispens[ae]|capitolo|handouts?|lecture notes)\b"#
    private static let admin = #"\b(programma|syllabus|regole|modalita d esame|calendario|exam rules|course schedule)\b"#

    /// ICU patterns, as strings: a `Regex` literal is not `Sendable`, and
    /// these are shared by every call.
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Lowercased, accents folded, separators to spaces: `Esiti_31-08.PDF`
    /// becomes `esiti 31 08 pdf`, so `\b` sees the words a person would.
    static func normalise(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it"))
            .lowercased()
            .replacingOccurrences(of: #"[_\-.'’]+"#, with: " ", options: .regularExpression)
    }
}
