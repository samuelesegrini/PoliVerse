import Foundation

/// Writes ``EntityIndex`` into the shared container, so App Intents can name
/// the student's courses, sittings and rooms from a process where none of the
/// app's services exist.
///
/// Written beside the Spotlight index and from the same material, because the
/// two answer the same question — "what does this student have?" — to two
/// different parts of the system.
nonisolated enum EntityIndexWriter {
    /// Narrows the live models to the stored records and saves them.
    ///
    /// Hidden courses are left out, as they are from Spotlight: a teaching the
    /// student has put away should not come back when Siri is asked.
    ///
    /// - Parameters:
    ///   - courses: The enrolled teachings.
    ///   - rooms: The room catalogue.
    ///   - exams: The exam sittings.
    ///   - account: The matricola to file the record under. Nothing is written
    ///     without one: an anonymous record is either sample data or a
    ///     signed-out state.
    static func write(courses: [Course], rooms: [Classroom], exams: [ExamSession], account: String?) {
        guard let account else { return }
        let index = EntityIndex(
            courses: courses.filter { !$0.isHidden }.map {
                EntityIndex.CourseRecord(id: $0.id, name: $0.name, code: $0.code,
                                         teacher: $0.teacher == "—" ? nil : $0.teacher,
                                         cfu: $0.cfu, academicYear: $0.academicYear)
            },
            exams: exams.map {
                EntityIndex.ExamRecord(id: $0.id, courseName: $0.courseName, courseCode: $0.courseCode,
                                       date: $0.date, room: $0.room,
                                       enrolmentCloses: $0.enrolmentCloses, grade: $0.grade?.value)
            },
            rooms: rooms.map {
                EntityIndex.RoomRecord(id: $0.id, name: RoomNaming.sentence($0.id),
                                       building: $0.buildingName, campus: $0.campusName,
                                       seats: $0.capacity)
            })
        OfflineStore.shared.save(index, as: EntityIndex.cacheName, account: account)
    }
}
