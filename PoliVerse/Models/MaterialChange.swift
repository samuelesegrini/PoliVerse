import Foundation

/// The course a WeBeep listing belongs to.
nonisolated struct MaterialCourse: Sendable, Equatable {
    let moodleID: Int
    /// The Politecnico teaching code where the title carries one; otherwise
    /// `moodle-<id>`, which is still stable and never collides with a code.
    let code: String
    let name: String

    init(moodleID: Int, code: String, name: String) {
        self.moodleID = moodleID
        self.code = code
        self.name = name
    }

    /// Only for a course that knows its Moodle id — never one matched by name.
    init?(_ course: Course) {
        guard let moodleID = course.moodleID else { return nil }
        self.init(moodleID: moodleID, code: course.code ?? course.id, name: course.name)
    }
}

/// The student's sittings of a course around the moment a listing is read —
/// what separates "a results file was posted" from "results for the sitting
/// you just took".
nonisolated struct MaterialContext: Sendable, Equatable {
    /// The most recent sitting the student took, within two months.
    let lastSat: Date?
    /// The next sitting the student is enrolled in, within a fortnight.
    let next: Date?

    static let none = MaterialContext(lastSat: nil, next: nil)
}

/// A results file that may be read, if the student allowed it.
///
/// The URL is the listing's own, without a token: the token is added only at
/// the moment of download, and neither is ever stored.
nonisolated struct ResultsFileRef: Sendable, Equatable {
    let fileURL: String
    let name: String
    let mimetype: String?
    var size: Int? = nil
}

/// One item of a WeBeep course page, reduced to what a change is made of.
nonisolated struct MaterialItem: Sendable, Equatable {
    /// `cm:<module id><path><file name>` for a file, `cm:<module id>` for a
    /// module with none — stable across listings and across renames of the
    /// section around it.
    let id: String
    let moduleID: Int
    let name: String
    let size: Int?
    let modified: Int?
    let tags: Set<DocumentTag>
    var fileURL: String? = nil
    var mimetype: String? = nil

    /// Changes when the file does. Moodle's listing has no content hash; size
    /// and modification time are what it offers, and both are free.
    var version: String { "\(size ?? -1)@\(modified ?? -1)" }

    /// Flattens a listing, keeping the teacher's order.
    ///
    /// Labels are skipped: they are text on the page, not items, and their
    /// edits say nothing a student can act on.
    static func items(from sections: [MoodleSection]) -> [MaterialItem] {
        sections.flatMap { section in
            (section.modules ?? []).flatMap { module -> [MaterialItem] in
                guard module.modname != "label" else { return [] }
                let files = (module.contents ?? []).filter { $0.type == "file" && $0.filename != nil }
                guard !files.isEmpty else {
                    return [MaterialItem(
                        id: "cm:\(module.id)", moduleID: module.id, name: module.name,
                        size: nil, modified: nil,
                        tags: DocumentClassifier.tags(
                            fileName: "", moduleName: module.name, sectionName: section.name,
                            modname: module.modname, mimetype: nil))]
                }
                return files.map { content in
                    let name = content.filename ?? module.name
                    return MaterialItem(
                        id: "cm:\(module.id)\(content.filepath ?? "/")\(name)",
                        moduleID: module.id, name: name,
                        size: content.filesize, modified: content.timemodified,
                        tags: DocumentClassifier.tags(
                            fileName: name, moduleName: module.name, sectionName: section.name,
                            modname: module.modname, mimetype: content.mimetype),
                        fileURL: content.fileurl, mimetype: content.mimetype)
                }
            }
        }
    }
}

/// What is kept of one course's last listing: enough to tell new from
/// changed, and nothing whose shape could stop the log decoding later.
nonisolated struct MaterialSnapshot: Sendable, Equatable, Codable {
    /// Item id → version.
    var versions: [String: String]
    /// Item id → the notable kind it was read as, by raw value — a string, so
    /// renaming a kind can never make a stored log unreadable.
    var notable: [String: String]
    var takenAt: Date
}

/// Compares two listings of one course and says what is new.
///
/// Like ``ExamChangeDetector``: pure, silent on the first listing, and it
/// never reads an empty listing as everything removed. Removals are not
/// reported — a teacher tidying a page is not news.
nonisolated enum MaterialChangeDetector {
    struct Result: Sendable {
        let updates: [ExamUpdate]
        let snapshot: MaterialSnapshot
        /// The file behind each results update, by update id.
        var files: [String: ResultsFileRef] = [:]
    }

    /// A snapshot older than this is a new baseline: a page last read months
    /// ago would otherwise announce everything posted since as news.
    static let staleAfter: TimeInterval = 14 * 86400

    static func detect(
        previous: MaterialSnapshot?,
        current: [MaterialItem],
        course: MaterialCourse,
        context: MaterialContext,
        now: Date
    ) -> Result {
        var snapshot = MaterialSnapshot(versions: [:], notable: [:], takenAt: now)
        for item in current {
            snapshot.versions[item.id] = item.version
            if let kind = kind(for: item) { snapshot.notable[item.id] = kind.rawValue }
        }

        guard let previous, now.timeIntervalSince(previous.takenAt) < staleAfter else {
            return Result(updates: [], snapshot: snapshot)
        }
        guard !current.isEmpty else { return Result(updates: [], snapshot: previous) }

        var updates: [ExamUpdate] = []
        var files: [String: ResultsFileRef] = [:]
        var ordinary: [MaterialItem] = []
        // Notable items gone from the listing: a file that reappears under a
        // new name is the same fact renamed, not a second one.
        var vanished = Dictionary(grouping: previous.notable.filter { snapshot.versions[$0.key] == nil },
                                  by: \.value).mapValues(\.count)

        for item in current {
            let oldVersion = previous.versions[item.id]
            if oldVersion == item.version { continue }

            guard let kind = kind(for: item) else {
                // Assignments are reported with their deadline by
                // ``AssignmentDetector``, not counted as files.
                if oldVersion == nil, !item.tags.contains(.assignment) { ordinary.append(item) }
                continue
            }

            // Replaced in place (edge case 10) or renamed (11): kept, but as a
            // correction rather than news.
            var replaced = oldVersion != nil
            if !replaced, let count = vanished[kind.rawValue], count > 0 {
                vanished[kind.rawValue] = count - 1
                replaced = true
            }

            let found = update(
                kind, course: course, context: context, now: now,
                // A name carrying both results and solutions is ambiguous
                // until something reads the file (§9.2, §10).
                confidence: item.tags.isSuperset(of: [.results, .solutions]) ? .probable : .high,
                evidence: "webeep:core_course_get_contents course=\(course.moodleID) cm=\(item.moduleID)",
                oldValue: replaced ? (oldVersion ?? "renamed") : nil,
                newValue: item.name,
                identity: "\(item.name)@\(item.version)")
            updates.append(found)
            // Solutions too: a file named for solutions can hold the marks.
            if kind == .resultsPosted || kind == .solutionsPosted, let url = item.fileURL {
                files[found.id] = ResultsFileRef(fileURL: url, name: item.name, mimetype: item.mimetype, size: item.size)
            }
        }

        if let first = ordinary.first {
            updates.append(update(
                .materialAdded, course: course, context: context, now: now, confidence: .high,
                evidence: "webeep:core_course_get_contents course=\(course.moodleID)",
                newValue: String(ordinary.count), identity: first.id))
        }

        return Result(updates: updates, snapshot: snapshot, files: files)
    }

    /// Results win over solutions and notices: they are what a student waits
    /// for, and an ambiguous name is marked as such rather than guessed.
    private static func kind(for item: MaterialItem) -> ExamUpdate.Kind? {
        if item.tags.contains(.results) { return .resultsPosted }
        if item.tags.contains(.solutions), !item.tags.contains(.exercise) { return .solutionsPosted }
        if item.tags.contains(.examNotice) { return .examNoticePosted }
        return nil
    }

    private static func update(
        _ kind: ExamUpdate.Kind, course: MaterialCourse, context: MaterialContext, now: Date,
        confidence: ExamUpdate.Confidence, evidence: String,
        oldValue: String? = nil, newValue: String, identity: String
    ) -> ExamUpdate {
        // Results and solutions concern the sitting just taken; a notice, the
        // one ahead.
        let sitting = kind == .examNoticePosted ? context.next : context.lastSat
        return ExamUpdate(
            kind: kind, examID: nil, courseCode: course.code, courseName: course.name,
            detectedAt: now, source: .webeep, confidence: confidence,
            evidence: evidence, oldValue: oldValue, newValue: newValue, identity: identity,
            wasEnrolled: sitting != nil, examDate: sitting)
    }
}
