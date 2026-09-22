import Foundation

/// The student's own things, in the shape Siri and the Shortcuts app can hold
/// them: courses, exam sittings and rooms, each with a stable identity and
/// enough words to be spoken back.
///
/// Deliberately narrower than the models it is built from, for the same reason
/// ``CareerSnapshot`` is narrower than the libretto: an intent may run outside
/// the app, in a process where none of the services exist, and the contract
/// with that process should be one small `Codable` type rather than the whole
/// domain.
///
/// Stored under ``cacheName`` in ``OfflineStore``, written whenever the app
/// re-indexes — see the indexing duty in `AppShellDuties`.
nonisolated struct EntityIndex: Codable, Sendable, Equatable {
    /// The teachings the student is enrolled in, hidden ones omitted.
    var courses: [CourseRecord]
    /// The sittings the career knows about, past and future.
    var exams: [ExamRecord]
    /// The rooms in the catalogue.
    var rooms: [RoomRecord]

    /// One teaching.
    nonisolated struct CourseRecord: Codable, Sendable, Equatable, Identifiable {
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
        /// The academic year it belongs to.
        var academicYear: String
    }

    /// One exam sitting.
    nonisolated struct ExamRecord: Codable, Sendable, Equatable, Identifiable {
        /// The sitting's identity, as ``ExamSession/id`` spells it.
        var id: Int
        /// The teaching's name.
        var courseName: String
        /// The teaching's code.
        var courseCode: String
        /// When the sitting is, where recorded.
        var date: Date?
        /// Where it is held, once published.
        var room: String?
        /// When the enrolment window closes, where recorded.
        var enrolmentCloses: Date?
        /// The mark, once published.
        var grade: Int?
    }

    /// One room.
    nonisolated struct RoomRecord: Codable, Sendable, Equatable, Identifiable {
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
    }

    /// The record name this index is stored under in the shared store.
    static let cacheName = "entity-index"

    /// An index with nothing in it, which is what a signed-out account has.
    static let empty = EntityIndex(courses: [], exams: [], rooms: [])

    /// Whether there is anything to answer with.
    var isEmpty: Bool { courses.isEmpty && exams.isEmpty && rooms.isEmpty }

    /// The index the app has last written for an account.
    ///
    /// - Parameters:
    ///   - account: The matricola the record is filed under.
    ///   - store: The store to read from. Defaults to the shared one.
    /// - Returns: The index, or ``empty`` when none has been written.
    static func load(account: String?, store: OfflineStore = .shared) -> EntityIndex {
        guard let account else { return .empty }
        return store.load(EntityIndex.self, as: cacheName, account: account)?.value ?? .empty
    }
}
