import AppIntents
import Foundation

/// The student's own things as App Entities, so Siri and the Shortcuts app can
/// name one and act on it.
///
/// Before this, every intent was screen-level: "apri l'orario", "apri la
/// carriera". An entity lets the question carry its subject — "quando è
/// l'esame di Analisi", "l'aula 3.0.1 è libera" — and lets a student build a
/// shortcut around a course they pick once from a list.
///
/// Every query reads ``EntityIndex`` from the shared container rather than the
/// live services, for the reason the widgets do: an intent can run in a process
/// where the app's own models never existed.

// MARK: - Courses

/// One teaching the student is enrolled in.
struct CourseEntity: AppEntity, Identifiable {
    /// How this kind of thing is named in the Shortcuts library.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Corso")
    /// The query that finds courses by identity or by name.
    static let defaultQuery = CourseEntityQuery()

    /// The teaching's identity, as ``Course/id`` spells it.
    var id: String
    /// The teaching's name.
    var name: String
    /// The teaching's code, where one is known.
    var code: String?
    /// Who teaches it.
    var teacher: String?
    /// Its credits.
    var cfu: Int

    /// How one course reads in a list and when Siri speaks it.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\([teacher, cfu > 0 ? String(localized: "\(cfu) CFU") : nil].compactMap { $0 }.joined(separator: " · "))",
            image: .init(systemName: "books.vertical"))
    }

    /// Builds an entity from a stored record.
    ///
    /// - Parameter record: The record from ``EntityIndex``.
    init(_ record: EntityIndex.CourseRecord) {
        id = record.id
        name = record.name
        code = record.code
        teacher = record.teacher
        cfu = record.cfu
    }
}

/// Finds courses in the index the app last wrote.
struct CourseEntityQuery: EntityStringQuery {
    /// The courses with the given identities.
    ///
    /// - Parameter identifiers: The identities Shortcuts stored.
    /// - Returns: The matching courses, in the index's own order.
    func entities(for identifiers: [CourseEntity.ID]) async throws -> [CourseEntity] {
        let wanted = Set(identifiers)
        return EntityIndex.load(account: SharedAccount.matricola)
            .courses.filter { wanted.contains($0.id) }.map(CourseEntity.init)
    }

    /// The courses whose name or code contains what was typed or said.
    ///
    /// - Parameter string: The words to match.
    /// - Returns: The matching courses.
    func entities(matching string: String) async throws -> [CourseEntity] {
        EntityIndex.load(account: SharedAccount.matricola).courses
            .filter { $0.name.localizedCaseInsensitiveContains(string)
                || ($0.code?.localizedCaseInsensitiveContains(string) ?? false) }
            .map(CourseEntity.init)
    }

    /// Every course, which is what the parameter's picker offers.
    ///
    /// - Returns: The courses.
    func suggestedEntities() async throws -> [CourseEntity] {
        EntityIndex.load(account: SharedAccount.matricola).courses.map(CourseEntity.init)
    }
}

// MARK: - Exams

/// One exam sitting from the student's career.
struct ExamEntity: AppEntity, Identifiable {
    /// How this kind of thing is named in the Shortcuts library.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Appello")
    /// The query that finds sittings by identity or by teaching name.
    static let defaultQuery = ExamEntityQuery()

    /// The sitting's identity, as ``ExamSession/id`` spells it.
    var id: Int
    /// The teaching's name.
    var courseName: String
    /// When the sitting is, where recorded.
    var date: Date?
    /// Where it is held, once published.
    var room: String?
    /// When the enrolment window closes, where recorded.
    var enrolmentCloses: Date?

    /// How one sitting reads in a list and when Siri speaks it.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(courseName)",
            subtitle: "\(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "data da definire"))",
            image: .init(systemName: "graduationcap"))
    }

    /// Builds an entity from a stored record.
    ///
    /// - Parameter record: The record from ``EntityIndex``.
    init(_ record: EntityIndex.ExamRecord) {
        id = record.id
        courseName = record.courseName
        date = record.date
        room = record.room
        enrolmentCloses = record.enrolmentCloses
    }
}

/// Finds exam sittings in the index the app last wrote.
struct ExamEntityQuery: EntityStringQuery {
    /// The sittings with the given identities.
    ///
    /// - Parameter identifiers: The identities Shortcuts stored.
    /// - Returns: The matching sittings.
    func entities(for identifiers: [ExamEntity.ID]) async throws -> [ExamEntity] {
        let wanted = Set(identifiers)
        return EntityIndex.load(account: SharedAccount.matricola)
            .exams.filter { wanted.contains($0.id) }.map(ExamEntity.init)
    }

    /// The sittings whose teaching name or code contains what was typed or said.
    ///
    /// - Parameter string: The words to match.
    /// - Returns: The matching sittings.
    func entities(matching string: String) async throws -> [ExamEntity] {
        EntityIndex.load(account: SharedAccount.matricola).exams
            .filter { $0.courseName.localizedCaseInsensitiveContains(string)
                || $0.courseCode.localizedCaseInsensitiveContains(string) }
            .map(ExamEntity.init)
    }

    /// The sittings still ahead, soonest first: a picker of last year's
    /// sittings would be a list of things nobody can act on.
    ///
    /// - Returns: The sittings.
    func suggestedEntities() async throws -> [ExamEntity] {
        EntityIndex.load(account: SharedAccount.matricola).exams
            .filter { ($0.date ?? .distantPast) >= .now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            .map(ExamEntity.init)
    }
}

// MARK: - Rooms

/// One room in the campus catalogue.
struct RoomEntity: AppEntity, Identifiable {
    /// How this kind of thing is named in the Shortcuts library.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Aula")
    /// The query that finds rooms by identity or by name.
    static let defaultQuery = RoomEntityQuery()

    /// The room's identity, as ``Classroom/id`` spells it.
    var id: String
    /// The room as it is signposted.
    var name: String
    /// The building it is in, where known.
    var building: String?
    /// The campus it is on, where known.
    var campus: String?
    /// Seating capacity.
    var seats: Int

    /// How one room reads in a list and when Siri speaks it.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\([building, campus].compactMap { $0 }.joined(separator: " · "))",
            image: .init(systemName: "door.left.hand.open"))
    }

    /// Builds an entity from a stored record.
    ///
    /// - Parameter record: The record from ``EntityIndex``.
    init(_ record: EntityIndex.RoomRecord) {
        id = record.id
        name = record.name
        building = record.building
        campus = record.campus
        seats = record.seats
    }
}

/// Finds rooms in the index the app last wrote.
struct RoomEntityQuery: EntityStringQuery {
    /// The rooms with the given identities.
    ///
    /// - Parameter identifiers: The identities Shortcuts stored.
    /// - Returns: The matching rooms.
    func entities(for identifiers: [RoomEntity.ID]) async throws -> [RoomEntity] {
        let wanted = Set(identifiers)
        return EntityIndex.load(account: SharedAccount.matricola)
            .rooms.filter { wanted.contains($0.id) }.map(RoomEntity.init)
    }

    /// The rooms whose name or building contains what was typed or said.
    ///
    /// - Parameter string: The words to match.
    /// - Returns: The matching rooms.
    func entities(matching string: String) async throws -> [RoomEntity] {
        EntityIndex.load(account: SharedAccount.matricola).rooms
            .filter { $0.name.localizedCaseInsensitiveContains(string)
                || ($0.building?.localizedCaseInsensitiveContains(string) ?? false) }
            .map(RoomEntity.init)
    }

    /// Nothing is suggested: the catalogue runs to hundreds of rooms, and a
    /// picker of all of them is a worse way in than typing three characters.
    ///
    /// - Returns: An empty list.
    func suggestedEntities() async throws -> [RoomEntity] { [] }
}
