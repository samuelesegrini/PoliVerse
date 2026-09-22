import Foundation
import Observation

/// Which release's notes the student has already been shown.
///
/// Kept beside ``OnboardingState`` and for the same reason: it is true of the install
/// rather than of the account, so signing out to switch career must not replay an
/// update's notes.
///
/// A fresh install is stamped without showing anything — see ``adoptFirstRun()``.
@MainActor
@Observable
final class WhatsNewState {
    /// Defaults key holding the last version whose notes were shown.
    private static let seenKey = "lastSeenReleaseVersion"

    /// The build's own `CFBundleShortVersionString`. Injectable, so tests are not run
    /// against whatever the bundle happens to say.
    private let current: String
    /// Where the last seen version is stored.
    private let defaults: UserDefaults

    /// The version whose notes were last shown, or `nil` on an install that predates this
    /// screen.
    private(set) var lastSeen: String?
    /// The notes currently on screen. The sheet binds to it.
    var showing: [ReleaseNote] = []

    /// Reads the last seen version.
    ///
    /// - Parameters:
    ///   - current: The version now running.
    ///   - defaults: Where the last seen version is stored.
    init(current: String = Bundle.main.releaseVersion, defaults: UserDefaults = .standard) {
        self.current = current
        self.defaults = defaults
        lastSeen = defaults.string(forKey: Self.seenKey)
    }

    /// The notes that apply right now, without marking them seen.
    var pending: [ReleaseNote] {
        ReleaseNotes.unseen(since: lastSeen, upTo: current)
    }

    /// Shows this launch's notes, if there are any.
    ///
    /// Called once the app is past the first run, since during onboarding there is nothing
    /// for anything to be new relative to. When there is nothing to say, the version is
    /// still stamped, so a later release compares against this one rather than against
    /// whatever was last interesting.
    func presentIfNeeded() {
        let notes = pending
        guard !notes.isEmpty else {
            // Nothing to say, but this version has still been reached: stamp
            // it, so a later release compares against this one rather than
            // against whatever was last interesting.
            markSeen()
            return
        }
        showing = notes
    }

    /// The notes for the version in use, for the row in Impostazioni that opens them again.
    ///
    /// Presented by whoever asks: a second sheet raised from the shell while Impostazioni is
    /// up would never appear.
    var currentNotes: [ReleaseNote] {
        ReleaseNotes.note(for: current).map { [$0] } ?? []
    }

    /// Records that this version's notes have been shown.
    func markSeen() {
        guard lastSeen != current else { return }
        lastSeen = current
        defaults.set(current, forKey: Self.seenKey)
    }

    /// Closes the notes and marks them seen.
    func dismiss() {
        showing = []
        markSeen()
    }

    /// Stamps the version without showing anything.
    ///
    /// For the end of the first run: the tour has just said what the app does, and following
    /// it with what is new since a version the student never had would be nonsense.
    func adoptFirstRun() {
        markSeen()
    }

    /// Whether the row in Impostazioni has anything to open.
    var hasCurrentNote: Bool { !currentNotes.isEmpty }
}

/// The version string release notes are matched against.
extension Bundle {
    /// `CFBundleShortVersionString` alone, without the build number ``appVersion`` adds, or
    /// `"0"` when the bundle has none.
    var releaseVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
