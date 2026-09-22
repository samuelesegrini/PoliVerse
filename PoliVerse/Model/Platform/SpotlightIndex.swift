import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Publishes the student's own data to system search.
///
/// What is indexed is deliberately narrow: courses, rooms, lecturers and exam
/// sittings — things with a stable identity and a screen to open. News and
/// notifications are not indexed: they are the university's content rather than the
/// student's, they churn, and leaving someone's notifications in the system index
/// after they stop using the app is not a worthwhile trade.
///
/// Everything is filed under ``domain``, so ``clear()`` removes the lot in one call.
@MainActor
final class SpotlightIndex {
    /// The domain every indexed item is filed under.
    static let domain = "segrini.samuele.PoliVerse.items"
    /// The activity type a Spotlight hit arrives as, carrying an ``Item`` identifier.
    static let activityType = "segrini.samuele.PoliVerse.open"

    /// The system index items are written to.
    private let index = CSSearchableIndex.default()
    /// Diagnostic log for this type, under the `spotlight` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "spotlight")

    /// An indexed thing, and which screen opening it should reach.
    ///
    /// The kind is encoded in the identifier rather than kept in a side table, because
    /// Spotlight hands back only that string — possibly long after the app last ran.
    nonisolated enum Item: Sendable, Equatable {
        /// A course by ``Course/id``, a room by ``Classroom/id``, a lecturer by
        /// ``Teacher/id``, or an exam sitting by ``ExamSession/id``.
        case course(String), room(String), teacher(String), exam(String)

        /// The `kind:value` string Spotlight stores and hands back.
        var identifier: String {
            switch self {
            case .course(let id): "course:\(id)"
            case .room(let id): "room:\(id)"
            case .teacher(let id): "teacher:\(id)"
            case .exam(let id): "exam:\(id)"
            }
        }

        /// Parses an identifier Spotlight handed back.
        ///
        /// - Parameter identifier: The stored string.
        /// - Returns: `nil` when it is not `kind:value` with a known kind.
        init?(identifier: String) {
            let parts = identifier.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let value = String(parts[1])
            switch parts[0] {
            case "course": self = .course(value)
            case "room": self = .room(value)
            case "teacher": self = .teacher(value)
            case "exam": self = .exam(value)
            default: return nil
            }
        }
    }

    /// Replaces the index with the student's current data.
    ///
    /// Hidden courses are omitted. Lecturers are indexed as contacts and everything else
    /// as content. Does nothing when there is nothing to index.
    ///
    /// - Parameters:
    ///   - courses: The enrolled teachings.
    ///   - rooms: The room catalogue.
    ///   - teachers: The lecturer roster.
    ///   - exams: The exam sittings.
    func index(courses: [Course], rooms: [Classroom],
               teachers: [Teacher], exams: [ExamSession]) {
        var items: [CSSearchableItem] = []

        for course in courses where !course.isHidden {
            items.append(item(
                Item.course(course.id), title: course.name,
                description: [course.teacher, course.academicYear]
                    .filter { $0 != "—" }.joined(separator: " · "),
                keywords: [course.code, course.teacher].compactMap { $0 },
                type: .content))
        }

        for room in rooms {
            items.append(item(
                Item.room(room.id), title: RoomNaming.sentence(room.id),
                description: [room.locationLabel, "\(room.capacity) posti"]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                keywords: [room.buildingName, room.campusName].compactMap { $0 },
                type: .content))
        }

        for teacher in teachers {
            items.append(item(
                Item.teacher(teacher.id), title: teacher.name,
                description: teacher.courses.map(\.name).joined(separator: ", "),
                keywords: [teacher.email].compactMap { $0 },
                type: .contact))
        }

        for exam in exams {
            items.append(item(
                Item.exam(String(exam.id)), title: "Appello · \(exam.courseName)",
                description: exam.date?.formatted(date: .long, time: .shortened) ?? "",
                keywords: [exam.room].compactMap { $0 },
                type: .content))
        }

        guard !items.isEmpty else { return }
        let count = items.count
        index.indexSearchableItems(items) { [log] error in
            if let error {
                log.error("Spotlight indexing failed: \(error.localizedDescription)")
            } else {
                log.notice("Indexed \(count, privacy: .public) items for Spotlight")
                DiagnosticsLog.shared.spotlightIndexed(count: count)
            }
        }
    }

    /// Removes everything this app indexed.
    ///
    /// Called on sign-out: without it, another person signing in on the same device would
    /// find the previous student's courses in Spotlight.
    func clear() {
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { [log] error in
            if let error {
                log.error("Could not clear the Spotlight index: \(error.localizedDescription)")
            }
        }
    }

    /// Builds one searchable item.
    ///
    /// Ranked slightly above the default, since these are things the student looks up,
    /// and set to expire after thirty days — long enough to survive a holiday, short
    /// enough that a stale list ages out on its own.
    ///
    /// - Parameters:
    ///   - item: What is being indexed.
    ///   - title: The item's title in search results.
    ///   - description: The second line.
    ///   - keywords: Extra terms to match on. Empty ones are dropped.
    ///   - type: The content type, which decides how the result is presented.
    /// - Returns: The item, ready to index.
    private func item(_ item: Item, title: String, description: String,
                      keywords: [String], type: UTType) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: type)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = keywords.filter { !$0.isEmpty }
        // Ranked below the user's own content by default; these are things
        // they look up, so nudge them up.
        attributes.rankingHint = 50

        let searchable = CSSearchableItem(
            uniqueIdentifier: item.identifier,
            domainIdentifier: Self.domain,
            attributeSet: attributes)
        // A month: long enough to survive a holiday, short enough that a
        // stale course list ages out on its own.
        searchable.expirationDate = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        return searchable
    }
}
