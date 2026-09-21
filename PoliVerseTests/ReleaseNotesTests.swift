import Foundation
import Testing
@testable import PoliVerse

/// The "Novità" screen is shown exactly once per update, and getting that
/// wrong is felt in both directions: showing it to someone who has just
/// installed the app is a list of changes to a version they never ran, and
/// missing it means the release goes unannounced until the next one.
@Suite("Novità di PoliVerse")
struct ReleaseNotesTests {
    private let notes = [
        ReleaseNote(version: "2.1", headline: "Due", items: [.init(symbol: "a", title: "A", detail: "a")]),
        ReleaseNote(version: "2.0", headline: "Uno", items: [.init(symbol: "b", title: "B", detail: "b")]),
    ]

    // MARK: Le versioni

    /// "2.10" comes after "2.9", which comparing the strings gets backwards.
    @Test("Le versioni si confrontano a numeri, non a stringhe")
    func ordering() {
        #expect(ReleaseNotes.isOlder("2.9", than: "2.10"))
        #expect(!ReleaseNotes.isOlder("2.10", than: "2.9"))
        #expect(ReleaseNotes.isOlder("1.9.3", than: "2.0"))
        #expect(!ReleaseNotes.isOlder("2.0", than: "2.0"))
    }

    /// A component that is not written counts as zero, so the same release
    /// spelled two ways is one release.
    @Test("Una componente mancante vale zero")
    func missingComponents() {
        #expect(!ReleaseNotes.isOlder("2", than: "2.0"))
        #expect(!ReleaseNotes.isOlder("2.0", than: "2"))
        #expect(ReleaseNotes.isOlder("2", than: "2.0.1"))
    }

    // MARK: Cosa mostrare

    @Test("Chi arriva da una versione precedente vede solo quello che si è perso")
    func showsWhatWasMissed() {
        let unseen = ReleaseNotes.unseen(in: notes, since: "2.0", upTo: "2.1")
        #expect(unseen.map(\.version) == ["2.1"])
    }

    /// Two updates in one go: both are told, newest first, rather than only
    /// the last.
    @Test("Chi salta un aggiornamento le vede tutte, dalla più recente")
    func catchesUp() {
        let three = [ReleaseNote(version: "2.2", headline: "Tre", items: [])] + notes
        let unseen = ReleaseNotes.unseen(in: three, since: "2.0", upTo: "2.2")
        #expect(unseen.map(\.version) == ["2.2", "2.1"])
    }

    /// The version being caught up *to* is included; anything past it is not —
    /// a note written for a release that has not shipped stays unseen.
    @Test("Una nota di una versione futura non si mostra")
    func doesNotLeakFutureNotes() {
        let three = [ReleaseNote(version: "3.0", headline: "Futuro", items: [])] + notes
        let unseen = ReleaseNotes.unseen(in: three, since: "2.0", upTo: "2.1")
        #expect(unseen.map(\.version) == ["2.1"])
    }

    @Test("Chi è già alla versione in uso non vede niente")
    func nothingWhenCurrent() {
        #expect(ReleaseNotes.unseen(in: notes, since: "2.1", upTo: "2.1").isEmpty)
    }

    /// A version with nothing written for it ships without a screen, which is
    /// how a bug-fix release goes out quietly.
    @Test("Una versione senza note non mostra niente")
    func silentRelease() {
        #expect(ReleaseNotes.unseen(in: notes, since: nil, upTo: "9.9").isEmpty)
        #expect(ReleaseNotes.unseen(in: notes, since: "2.1", upTo: "2.2").isEmpty)
    }

    /// An install from before this screen existed has no history to replay:
    /// it is told about the release it has just landed on, not about every
    /// release ever written.
    @Test("Senza una versione vista si mostra solo quella in uso")
    func firstTimeShowsOnlyCurrent() {
        let shown = ReleaseNotes.unseen(in: notes, since: nil, upTo: "2.1")
        #expect(shown.map(\.version) == ["2.1"], "Non deve srotolare tutta la storia delle versioni")
    }

    // MARK: Lo stato

    @MainActor
    private func state(current: String, seen: String?) -> WhatsNewState {
        let suite = "release-notes-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if let seen { defaults.set(seen, forKey: "lastSeenReleaseVersion") }
        return WhatsNewState(current: current, defaults: defaults)
    }

    @MainActor
    @Test("Una versione senza novità viene comunque segnata come vista")
    func stampsEvenWithoutNotes() {
        let state = state(current: "9.9", seen: nil)
        state.presentIfNeeded()
        #expect(state.showing.isEmpty)
        #expect(state.lastSeen == "9.9", "La prossima release deve confrontarsi con questa, non con l'ultima interessante")
    }

    /// The first run ends by stamping the version, so the tour is not followed
    /// by a list of what changed since a version that was never installed.
    @MainActor
    @Test("Finita la prima configurazione non si mostrano le novità")
    func firstRunShowsNothing() {
        let version = ReleaseNotes.all.first?.version ?? "2.0"
        let state = state(current: version, seen: nil)
        state.adoptFirstRun()
        state.presentIfNeeded()
        #expect(state.showing.isEmpty)
    }

    /// An install that predates the screen has no stamp, and that is exactly
    /// the case that should be told.
    @MainActor
    @Test("Chi aggiorna da prima di questa schermata le vede")
    func upgradeFromBeforeTheScreen() {
        let version = ReleaseNotes.all.first?.version ?? "2.0"
        let state = state(current: version, seen: nil)
        state.presentIfNeeded()
        #expect(!state.showing.isEmpty)
    }

    @MainActor
    @Test("Chiudendole restano chiuse anche al rilancio")
    func dismissSticks() {
        let version = ReleaseNotes.all.first?.version ?? "2.0"
        let state = state(current: version, seen: nil)
        state.presentIfNeeded()
        state.dismiss()
        #expect(state.showing.isEmpty)
        state.presentIfNeeded()
        #expect(state.showing.isEmpty)
    }

    /// Every note written must have a headline and items worth a screen — an
    /// empty release note is a screen that says nothing.
    @Test("Le note scritte hanno un contenuto")
    func writtenNotesAreUseful() {
        for note in ReleaseNotes.all {
            #expect(!note.items.isEmpty, "La versione \(note.version) non elenca niente")
            #expect(note.items.count <= 5, "La versione \(note.version) elenca troppo per una schermata sola")
            #expect(!String(localized: note.headline).isEmpty)
        }
    }

    /// Two notes for one version means one of them is never shown.
    @Test("Ogni versione compare una volta sola")
    func versionsAreUnique() {
        let versions = ReleaseNotes.all.map(\.version)
        #expect(Set(versions).count == versions.count)
    }

    /// Newest first: the screen shows them in order and the catch-up relies on
    /// it.
    @Test("Le note sono in ordine, dalla più recente")
    func notesAreOrdered() {
        for (newer, older) in zip(ReleaseNotes.all, ReleaseNotes.all.dropFirst()) {
            #expect(ReleaseNotes.isOlder(older.version, than: newer.version),
                    "\(older.version) dovrebbe venire dopo \(newer.version) nella lista")
        }
    }
}
