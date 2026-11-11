import Foundation
import Observation

/// The items marked as new, section by section, until the student has had the
/// section on screen.
///
/// A refresh that changes a stored copy says which items it added or changed
/// (``ChangeDetector``); they are marked here, kept per account on the phone so a
/// change found in the background is still marked at the next launch, and
/// unmarked once their section has been looked at. Identities only: nothing here
/// says what an item contains.
@MainActor
@Observable
final class NewMarks {
    /// The app's marks.
    static let shared = NewMarks()

    /// The name of the per-account file.
    nonisolated static let name = "new-marks"
    /// How long a section must stay on screen for its marks to count as seen: a
    /// page flicked past on the way elsewhere has not been looked at.
    nonisolated static let glance: Duration = .seconds(1)

    /// The marked identities of the account on screen, by section.
    private(set) var marked: [String: Set<String>] = [:]
    /// The identities marked a moment ago, by section: the rows that write
    /// themselves in when they appear.
    @ObservationIgnored private var recent: [String: (ids: Set<String>, at: ContinuousClock.Instant)] = [:]
    /// The matricola whose marks are shown. `nil` under sample data and signed out.
    @ObservationIgnored private var account: String?
    private let offline: OfflineStore

    /// Creates the marks. Nothing is read until ``show(account:)``.
    ///
    /// - Parameter offline: Where the per-account file lives.
    init(offline: OfflineStore = .shared) {
        self.offline = offline
    }

    /// Shows one account's marks, reading them from its file.
    ///
    /// - Parameter account: The matricola, or `nil` for sample data or signed out.
    func show(account: String?) {
        guard account != self.account else { return }
        self.account = account
        recent = [:]
        let stored = offline.load([String: Set<String>].self, as: Self.name, account: account)?.value ?? [:]
        if marked != stored { marked = stored }
    }

    /// Marks items of a section as new.
    ///
    /// Marks for an account that is not the one on screen are written to its file
    /// and shown to nobody: a load that outlived a sign-out must not mark another
    /// student's rows.
    ///
    /// - Parameters:
    ///   - ids: The identities of the items added or changed.
    ///   - section: The section they are shown in. A fixed word.
    ///   - account: Whose items they are, or `nil` under sample data.
    func mark(_ ids: Set<String>, in section: String, account: String?) {
        guard !ids.isEmpty else { return }
        guard account == self.account else {
            guard let account else { return }
            var stored = offline.load([String: Set<String>].self, as: Self.name, account: account)?.value ?? [:]
            stored[section, default: []].formUnion(ids)
            offline.save(stored, as: Self.name, account: account)
            return
        }
        marked[section, default: []].formUnion(ids)
        recent[section] = (ids, .now)
        save()
    }

    /// Whether an item is marked as new.
    ///
    /// - Parameters:
    ///   - id: The item's identity.
    ///   - section: The section it is shown in.
    func isNew(_ id: String, in section: String) -> Bool {
        marked[section]?.contains(id) ?? false
    }

    /// Whether an item was marked within the time a reveal takes: a row that
    /// appears now is one the refresh just added, not one marked days ago.
    ///
    /// - Parameters:
    ///   - id: The item's identity.
    ///   - section: The section it is shown in.
    func justMarked(_ id: String, in section: String) -> Bool {
        guard let last = recent[section], last.ids.contains(id) else { return false }
        return ContinuousClock.now - last.at < .seconds(RevealPlan.total)
    }

    /// Whether a section that was on screen for some time has been seen.
    ///
    /// - Parameter shown: How long it was on screen.
    nonisolated static func wasSeen(shownFor shown: Duration) -> Bool {
        shown >= glance
    }

    /// Removes a section's marks: the student has had it on screen.
    ///
    /// - Parameter section: The section.
    func seen(_ section: String) {
        guard marked[section]?.isEmpty == false else { return }
        marked[section] = nil
        recent[section] = nil
        save()
    }

    /// Forgets the marks on screen, for sign-out. The account's file goes with
    /// its other stored copies.
    func forget() {
        account = nil
        recent = [:]
        if !marked.isEmpty { marked = [:] }
    }

    private func save() {
        guard let account else { return }
        offline.save(marked, as: Self.name, account: account)
    }
}
