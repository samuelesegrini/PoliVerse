import Foundation
import Testing
@testable import PoliVerse

/// The career figures the profile shows.
@Suite("Profile summary")
struct ProfileSummaryTests {
    private func exam(_ id: String, _ grade: Int?, cfu: Int, day: Int?, lode: Bool = false) -> LibrettoExam {
        LibrettoExam(id: id, name: id, grade: grade, hasLode: lode, cfu: cfu,
                     date: day.map { Date(timeIntervalSince1970: TimeInterval($0) * 86_400) },
                     statusText: nil, isPassed: day != nil)
    }

    private let book = GradeBook(mean: 0, earnedCFU: 0, plannedCFU: 180, examsPlanned: 0, examsSubscribed: 0, examsGiven: 0)

    @Test("The mean is weighted by credits, marks sorted oldest first")
    func mean() throws {
        let summary = ProfileSummary(libretto: [exam("B", 30, cfu: 10, day: 20), exam("A", 24, cfu: 5, day: 10),
                                                exam("C", nil, cfu: 8, day: nil)],
                                     gradeBook: book, header: nil)
        #expect(try #require(summary.mean) == 28)
        #expect(summary.marks.map(\.id) == ["A", "B"])
        #expect(summary.earnedCFU == 15)
        #expect(summary.passedCount == 2)
        #expect(summary.pendingCount == 1)
    }

    @Test("Badges follow the numbers: first thirty, honours, high average")
    func badges() {
        let summary = ProfileSummary(libretto: [exam("A", 30, cfu: 10, day: 1, lode: true), exam("B", 28, cfu: 10, day: 2)],
                                     gradeBook: book, header: nil)
        #expect(summary.badges.contains(.firstThirty))
        #expect(summary.badges.contains(.honours))
        #expect(summary.badges.contains(.highAverage))
        #expect(!summary.badges.contains(.fiveExams))
        #expect(summary.best?.id == "A")
    }

    @Test("With no marks the official mean is used, or none")
    func fallback() {
        #expect(ProfileSummary(libretto: [], gradeBook: book, header: nil).mean == nil)
        var official = book
        official.mean = 26.5
        #expect(ProfileSummary(libretto: [], gradeBook: official, header: nil).mean == 26.5)
    }
}
