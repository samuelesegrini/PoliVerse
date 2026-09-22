import Foundation

/// The course a WeBeep listing belongs to.
nonisolated struct MaterialCourse: Sendable, Equatable {
    /// Moodle's course id, which every WeBeep call is keyed by.
    let moodleID: Int
    /// The Politecnico teaching code where the title carries one, and `moodle-<id>`
    /// otherwise — still stable, and it cannot collide with a real code.
    let code: String
    /// The teaching's name.
    let name: String

    /// Creates a course reference.
    ///
    /// - Parameters:
    ///   - moodleID: Moodle's course id.
    ///   - code: The teaching code, or a Moodle-derived stand-in.
    ///   - name: The teaching's name.
    init(moodleID: Int, code: String, name: String) {
        self.moodleID = moodleID
        self.code = code
        self.name = name
    }

    /// Builds a reference from a course.
    ///
    /// - Parameter course: The course.
    /// - Returns: `nil` for a course with no ``Course/moodleID``, which is one matched by
    ///   name rather than known to WeBeep.
    init?(_ course: Course) {
        guard let moodleID = course.moodleID else { return nil }
        self.init(moodleID: moodleID, code: course.code ?? course.id, name: course.name)
    }
}

/// The student's sittings of a course around the moment a listing is read.
///
/// This is what separates “a results file was posted” from “results for the sitting
/// you just took”.
nonisolated struct MaterialContext: Sendable, Equatable {
    /// The most recent sitting the student took, within two months.
    let lastSat: Date?
    /// The next sitting the student is enrolled in, within a fortnight.
    let next: Date?

    /// No sitting either side, which makes every finding a plain posting.
    static let none = MaterialContext(lastSat: nil, next: nil)
}

/// A results file that may be read, if the student allowed it.
///
/// The address is the listing's own, without a token: the token is added at the moment
/// of download, and neither is stored.
nonisolated struct ResultsFileRef: Sendable, Equatable {
    /// Where the file can be fetched, without a token.
    let fileURL: String
    /// The file's name.
    let name: String
    /// The file's media type, where Moodle records one.
    let mimetype: String?
    /// The file's size in bytes, where Moodle records it.
    var size: Int? = nil
}

/// One item of a WeBeep course page, reduced to what a change is made of.
nonisolated struct MaterialItem: Sendable, Equatable {
    /// `cm:<module id><path><file name>` for a file, `cm:<module id>` for a module with
    /// none.
    ///
    /// Stable across listings, and across a rename of the section around it.
    let id: String
    /// The course module the item belongs to.
    let moduleID: Int
    /// The file's name, or the module's when it holds no file.
    let name: String
    /// The file's size in bytes.
    let size: Int?
    /// When the file last changed, in epoch seconds.
    let modified: Int?
    /// What the item is about, from ``DocumentClassifier/tags(fileName:moduleName:sectionName:modname:mimetype:)``.
    let tags: Set<DocumentTag>
    /// Where the file can be fetched, without a token.
    var fileURL: String? = nil
    /// The file's media type.
    var mimetype: String? = nil

    /// What is compared between listings: the size and modification time together.
    ///
    /// Moodle's listing carries no content hash, and these two are what it does offer.
    var version: String { "\(size ?? -1)@\(modified ?? -1)" }

    /// Flattens a course listing into items, keeping the lecturer's order.
    ///
    /// A module with files yields one item per file; a module with none yields one item
    /// for itself. Labels are skipped: they are text on the page rather than items, and
    /// their edits say nothing a student can act on.
    ///
    /// - Parameter sections: The course's contents.
    /// - Returns: The items.
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

/// What is kept of one course's last listing: enough to tell new from changed, and
/// nothing whose shape could stop the stored log decoding later.
nonisolated struct MaterialSnapshot: Sendable, Equatable, Codable {
    /// Item id to ``MaterialItem/version``.
    var versions: [String: String]
    /// Item id to the notable kind it was read as, by raw value — a string, so renaming a
    /// kind cannot make a stored log unreadable.
    var notable: [String: String]
    /// When the listing was read.
    var takenAt: Date
}

/// Compares two listings of one course and says what is new.
///
/// Pure, like ``ExamChangeDetector``: silent on the first listing, treating a snapshot
/// older than ``staleAfter`` as a new baseline, and never reading an empty listing as
/// everything having been removed. Removals are not reported — a lecturer tidying a
/// page is not news.
///
/// Notable items — results, solutions and exam notices — are reported individually;
/// everything else new is collapsed into one ``ExamUpdate/Kind/materialAdded`` update
/// carrying a count.
nonisolated enum MaterialChangeDetector {
    /// What one comparison produced.
    struct Result: Sendable {
        /// What changed. Empty on a baseline listing.
        let updates: [ExamUpdate]
        /// The listing to compare the next one against. The previous snapshot is returned
        /// unchanged for an empty listing.
        let snapshot: MaterialSnapshot
        /// The file behind each results or solutions update, by update id, for the reader that
        /// may open it.
        var files: [String: ResultsFileRef] = [:]
    }

    /// How old a snapshot may be before it becomes a new baseline.
    ///
    /// A page last read months ago would otherwise announce everything posted since as
    /// news.
    static let staleAfter: TimeInterval = 14 * 86400

    /// Compares a course's listing against the previous one.
    ///
    /// A notable item that has vanished and reappeared under a new name is reported as a
    /// correction rather than as news, as is one replaced in place. A name that reads as
    /// both results and solutions is marked probable rather than guessed at.
    ///
    /// - Parameters:
    ///   - previous: The last listing, or `nil` for the first.
    ///   - current: This listing's items.
    ///   - course: The course being read.
    ///   - context: The sittings either side of this moment.
    ///   - now: The moment of this reading.
    /// - Returns: The updates, the new snapshot and the results files behind them.
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

    /// Which notable kind an item is, if any.
    ///
    /// Results win over solutions and notices, since they are what a student waits for.
    /// Solutions to an exercise sheet are not solutions to an exam.
    ///
    /// - Parameter item: The item to classify.
    /// - Returns: The kind, or `nil` for an ordinary item.
    private static func kind(for item: MaterialItem) -> ExamUpdate.Kind? {
        if item.tags.contains(.results) { return .resultsPosted }
        if item.tags.contains(.solutions), !item.tags.contains(.exercise) { return .solutionsPosted }
        if item.tags.contains(.examNotice) { return .examNoticePosted }
        return nil
    }

    /// Builds one material update, tying it to the sitting it concerns.
    ///
    /// Results and solutions concern the sitting just taken; a notice concerns the one
    /// ahead.
    ///
    /// - Parameters:
    ///   - kind: What happened.
    ///   - course: The course it happened in.
    ///   - context: The sittings either side of this moment.
    ///   - now: When it was noticed.
    ///   - confidence: How sure the reading is.
    ///   - evidence: The call and identifiers it was read from.
    ///   - oldValue: The previous version, for a replacement or a rename.
    ///   - newValue: The item's name, or the count for a collapsed update.
    ///   - identity: What makes this update distinct from the next.
    /// - Returns: The update.
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
