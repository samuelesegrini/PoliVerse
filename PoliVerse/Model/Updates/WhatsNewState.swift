import Foundation
import Observation

/// Which release the student has already been told about.
///
/// Kept beside ``OnboardingState`` and for the same reason: it is true of the
/// *install*, not of the account, so signing out to switch career must not
/// replay an update's notes.
///
/// A fresh install is stamped without showing anything — someone who has just
/// been through the tour does not need to be told what changed since a version
/// they never ran.
@MainActor
@Observable
final class WhatsNewState {
    private static let seenKey = "lastSeenReleaseVersion"

    /// The build's own version, injectable so the tests are not run against
    /// whatever the bundle happens to say.
    private let current: String
    private let defaults: UserDefaults

    private(set) var lastSeen: String?
    /// Set when the notes are on screen; the sheet binds to it.
    var showing: [ReleaseNote] = []

    init(current: String = Bundle.main.releaseVersion, defaults: UserDefaults = .standard) {
        self.current = current
        self.defaults = defaults
        lastSeen = defaults.string(forKey: Self.seenKey)
    }

    /// The notes that apply right now, without marking them seen.
    var pending: [ReleaseNote] {
        ReleaseNotes.unseen(since: lastSeen, upTo: current)
    }

    /// Shows the notes for this launch, if there are any.
    ///
    /// Called once the app is past the first run: during onboarding there is
    /// nothing to be "new" relative to.
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

    /// The notes for the version in use, for the row in Impostazioni that
    /// opens them again. Presented by whoever asks: a second sheet raised from
    /// the shell while Impostazioni is up would never appear.
    var currentNotes: [ReleaseNote] {
        ReleaseNotes.note(for: current).map { [$0] } ?? []
    }

    /// Remembers that this version's notes have been read.
    func markSeen() {
        guard lastSeen != current else { return }
        lastSeen = current
        defaults.set(current, forKey: Self.seenKey)
    }

    func dismiss() {
        showing = []
        markSeen()
    }

    /// Stamps the version without showing anything.
    ///
    /// For the end of the first run: the tour has just said what the app does,
    /// and following it with "what's new since a version you never had" would
    /// be nonsense.
    func adoptFirstRun() {
        markSeen()
    }

    /// Whether the row in Impostazioni has anything to open.
    var hasCurrentNote: Bool { !currentNotes.isEmpty }
}

extension Bundle {
    /// `CFBundleShortVersionString` alone — what ``ReleaseNote/version`` is
    /// matched against, without the build number ``appVersion`` adds.
    var releaseVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
