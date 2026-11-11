import Foundation

/// What a refresh changed in one part, by the identity of its items.
///
/// Identities only: what an item was and what it became stay in the values, and
/// whoever needs to word a change reads them there.
nonisolated struct ChangeSet: Equatable, Sendable {
    /// Items the stored copy did not have.
    var added: Set<String> = []
    /// Items in both whose content differs.
    var changed: Set<String> = []
    /// Items the stored copy had and the answer does not.
    var removed: Set<String> = []

    /// Whether the refresh changed nothing.
    var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
    /// The items worth pointing out to the student: those added and those changed.
    var marked: Set<String> { added.union(changed) }
}

/// Compares the items of a fetched part with those of its stored copy.
///
/// Values in, change set out. Items are matched by identity, so it only suits
/// data whose items keep their id from one answer to the next. Two cases are not
/// compared at all, because each is far more often a quirk of the service than
/// news: a stored copy with no items, which is a first look, and an answer with
/// no items, which the Politecnico's services give between sessions. Marking
/// forty sittings as new is worse than missing one.
nonisolated enum ChangeDetector {
    /// The changes from a stored copy's items to a fetched part's.
    ///
    /// - Parameters:
    ///   - old: The items of the stored copy.
    ///   - new: The items just fetched.
    /// - Returns: What was added, changed and removed. Empty when either side has
    ///   no items. Of two items with one id, the first counts.
    static func changes<Item: Identifiable & Equatable>(from old: [Item], to new: [Item]) -> ChangeSet {
        guard !old.isEmpty, !new.isEmpty else { return ChangeSet() }
        let before = Dictionary(old.map { (String(describing: $0.id), $0) }, uniquingKeysWith: { first, _ in first })
        var set = ChangeSet()
        var seen: Set<String> = []
        for item in new {
            let id = String(describing: item.id)
            guard seen.insert(id).inserted else { continue }
            if let was = before[id] {
                if was != item { set.changed.insert(id) }
            } else {
                set.added.insert(id)
            }
        }
        set.removed = Set(before.keys).subtracting(seen)
        return set
    }
}
