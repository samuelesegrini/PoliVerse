import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Publishes the student's own data to system search.
///
/// What gets indexed is deliberately narrow: courses, rooms, teachers and
/// exams — things with a stable identity and a screen to open. News and
/// notifications are not indexed, because they are the university's content
/// rather than the student's, they churn, and leaving somebody's private
/// notifications in the system index long after they stop using the app is
/// not a trade worth making.
///
/// Everything lives in one domain so a sign-out can delete the lot in a single
/// call.
@MainActor
final class SpotlightIndex {
    static let domain = "segrini.samuele.PoliVerse.items"
    /// Opening a Spotlight hit arrives as this activity type, carrying the
    /// identifier below.
    static let activityType = "segrini.samuele.PoliVerse.open"

    private let index = CSSearchableIndex.default()
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "spotlight")

    /// A stable identifier that also says which screen to open.
    ///
    /// Encoded in the id itself rather than kept in a side table: Spotlight
    /// hands back only this string, possibly long after the app was last run.
    nonisolated enum Item: Sendable, Equatable {
        case course(String), room(String), teacher(String), exam(String)

        var identifier: String {
            switch self {
            case .course(let id): "course:\(id)"
            case .room(let id): "room:\(id)"
            case .teacher(let id): "teacher:\(id)"
            case .exam(let id): "exam:\(id)"
            }
        }

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
                Item.room(room.id), title: "Aula \(room.id)",
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

    /// Removes everything on sign-out.
    ///
    /// Not optional politeness: without it another person signing in on the
    /// same device would find the previous student's courses in Spotlight.
    func clear() {
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { [log] error in
            if let error {
                log.error("Could not clear the Spotlight index: \(error.localizedDescription)")
            }
        }
    }

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
