import Foundation
import Testing
@testable import PoliVerse

/// Which WeBeep course pages a background pass reads.
@Suite("WeBeep watched courses")
struct WeBeepWatchTests {
    /// 2026-02-25: academic year 2025/26.
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func course(_ id: Int, year: String, favourite: Bool = false, hidden: Bool = false) -> Course {
        Course(id: "moodle-\(id)", name: "C\(id)", teacher: "—", cfu: 0, semester: "—",
               academicYear: year, moodleID: id, isFavourite: favourite, isHidden: hidden)
    }

    @Test("This year's visible pages, favourites first, capped")
    func watched() {
        let courses = [
            course(1, year: "2025-26"), course(2, year: "2024-25", favourite: true),
            course(3, year: "2025/26", hidden: true), course(4, year: "2025-2026", favourite: true),
        ] + (10..<20).map { course($0, year: "2025-26") }
        let watched = WeBeepService.watched(courses, now: now)
        #expect(watched.first?.moodleID == 4)
        #expect(!watched.contains { $0.moodleID == 2 || $0.moodleID == 3 })
        #expect(watched.count == WeBeepService.watchLimit)
    }
}
