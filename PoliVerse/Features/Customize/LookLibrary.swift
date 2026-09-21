import Foundation

/// Personalizza's saved looks and which one the page uses.
///
/// One commit point per action: saving an edit changes a look, using a look
/// makes it the page's. Editing never changes the page by itself.
nonisolated struct LookLibrary: Equatable, Sendable {
    private(set) var looks: [TodayStyle]
    private(set) var selection: Int

    init(looks: [TodayStyle], selection: Int) {
        self.looks = looks.isEmpty ? [TodayStyle()] : looks
        self.selection = min(max(selection, 0), self.looks.count - 1)
    }

    var active: TodayStyle { looks[selection] }

    /// One look always stays: the page needs one to show.
    var canRemove: Bool { looks.count > 1 }

    mutating func save(_ look: TodayStyle, at index: Int) {
        guard looks.indices.contains(index) else { return }
        looks[index] = look
    }

    mutating func use(_ index: Int) {
        guard looks.indices.contains(index) else { return }
        selection = index
    }

    mutating func append(_ look: TodayStyle) {
        looks.append(look)
    }

    /// Puts a look straight after another and returns where it landed: how
    /// `+` adds one, so the copy sits beside what it was copied from.
    @discardableResult
    mutating func insert(_ look: TodayStyle, after index: Int) -> Int {
        let place = min(max(index + 1, 0), looks.count)
        looks.insert(look, at: place)
        if place <= selection { selection += 1 }
        return place
    }

    mutating func rename(_ name: String, at index: Int) {
        guard looks.indices.contains(index) else { return }
        looks[index].name = name
    }

    /// Removes a look, keeping the one in use where it can; if that is the
    /// one removed, its neighbour takes over.
    @discardableResult
    mutating func remove(at index: Int) -> Bool {
        guard canRemove, looks.indices.contains(index) else { return false }
        looks.remove(at: index)
        if index < selection || selection == looks.count { selection -= 1 }
        selection = min(max(selection, 0), looks.count - 1)
        return true
    }
}
