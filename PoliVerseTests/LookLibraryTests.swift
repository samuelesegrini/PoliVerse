import Foundation
import Testing
@testable import PoliVerse

/// Personalizza's saved looks: saving edits one, using one makes it the
/// page's, and a look can be deleted without losing the one in use.
@Suite("Look library")
struct LookLibraryTests {
    private func library(_ count: Int, selection: Int) -> LookLibrary {
        var looks = Array(repeating: TodayStyle(), count: count)
        for index in looks.indices { looks[index].dateSize = 0.6 + Double(index) * 0.1 }
        return LookLibrary(looks: looks, selection: selection)
    }

    @Test("Saving an edit changes the look but not which one is in use")
    func save() {
        var library = library(3, selection: 0)
        var edited = library.looks[2]
        edited.dateColour = .flavor
        library.save(edited, at: 2)
        #expect(library.looks[2].dateColour == .flavor)
        #expect(library.selection == 0)
        #expect(library.active == library.looks[0])
    }

    @Test("Using a look makes it the one in use")
    func use() {
        var library = library(3, selection: 0)
        library.use(2)
        #expect(library.selection == 2)
        #expect(library.active == library.looks[2])
        library.use(9)
        #expect(library.selection == 2)
    }

    @Test("Deleting a look before the one in use keeps the same look in use")
    func deleteBefore() {
        var library = library(4, selection: 2)
        let inUse = library.active
        let removed = library.remove(at: 0)
        #expect(removed)
        #expect(library.looks.count == 3)
        #expect(library.active == inUse)
    }

    @Test("Deleting the look in use falls back to its neighbour; the last look cannot go")
    func deleteInUse() {
        var library = library(2, selection: 1)
        let removedInUse = library.remove(at: 1)
        #expect(removedInUse)
        #expect(library.selection == 0)
        #expect(!library.canRemove)
        let removedLast = library.remove(at: 0)
        #expect(!removedLast)
        #expect(library.looks.count == 1)
    }
}
