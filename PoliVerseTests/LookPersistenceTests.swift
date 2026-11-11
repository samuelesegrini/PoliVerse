import Foundation
import Testing
@testable import PoliVerse

@Suite("Look persistence")
struct LookPersistenceTests {
    @Test func identitySurvivesEditingAndRelaunch() throws {
        var library = LookLibrary(looks: [TodayStyle(), TodayStyle()], selection: 1)
        let id = library.ids[1]
        var edited = library.active
        edited.name = "Personale"
        library.save(edited, at: 1)
        let restored = try #require(LookLibrary(document: library.document))
        #expect(restored.ids[1] == id)
        #expect(restored.active.name == "Personale")
        #expect(restored.selection == 1)
        library.append(edited)
        #expect(library.ids[2] != id)
    }
    @Test func legacyMigrationKeepsOrderSelectionAndValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "look-migration-\(UUID().uuidString)"))
        var first = TodayStyle(); first.name = "Prima"
        var second = TodayStyle(); second.name = "Seconda"; second.special = .blueprint
        defaults.set(TodayStyle.encodeLibrary([first, second]), forKey: TodayStyle.libraryKey)
        defaults.set(1, forKey: TodayStyle.selectionKey)
        let migrated = LookLibrary.load(defaults)
        #expect(migrated.looks == [first, second])
        #expect(migrated.active == second)
        migrated.persist(to: defaults)
        #expect(LookLibrary.load(defaults) == migrated)
        #expect(TodayStyle.library(from: migrated.document, active: second) == [first, second])
    }

    @Test func deletionUndoRestoresIdentityAndActiveLook() {
        var library = LookLibrary(looks: [TodayStyle(), TodayStyle()], selection: 1)
        let id = library.ids[1], look = library.active
        let didRemove = library.remove(at: 1)
        #expect(didRemove)
        library.restore(look, at: 1, selection: 1, id: id)
        #expect(library.ids[1] == id)
        #expect(library.selection == 1)
    }

    @Test @MainActor func saveDoesNotApplyAndPreservesIdentity() {
        var library = LookLibrary(looks: [TodayStyle(), TodayStyle()], selection: 0)
        let id = library.ids[1], active = library.active
        var draft = library.looks[1]; draft.name = "Bozza"
        let session = LookEditingSession(draft: draft, original: library.looks[1], index: 1)
        #expect(session.save(in: &library) == 1)
        #expect(library.active == active)
        #expect(library.selection == 0)
        #expect(library.ids[1] == id)
        #expect(library.looks[1].name == "Bozza")
    }

    @Test func unreadableDocumentIsNeverOverwrittenByOpening() throws {
        let defaults = try #require(UserDefaults(suiteName: "look-future-\(UUID().uuidString)"))
        for document in [#"{"version":99,"entries":[]}"#, #"{"version":2,"entries":"broken"}"#, #"{"version":2,"entries" : ["#] {
            defaults.set(document, forKey: TodayStyle.libraryKey)
            let library = LookLibrary.load(defaults)
            #expect(!library.canPersist)
            library.persist(to: defaults)
            #expect(defaults.string(forKey: TodayStyle.libraryKey) == document)
        }
    }

}
