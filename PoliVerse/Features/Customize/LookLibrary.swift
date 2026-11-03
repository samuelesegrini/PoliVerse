import Foundation

/// Personalizza's saved looks and which one the page uses.
///
/// One commit point per action: saving an edit changes a look, using a look
/// makes it the page's. Editing never changes the page by itself.
nonisolated struct LookLibrary: Equatable, Sendable {
    private(set) var looks: [TodayStyle]
    private(set) var canPersist = true
    private(set) var ids: [UUID]
    private(set) var selection: Int

    /// The library, with at least one look and a selection inside it.
    ///
    /// - Parameters:
    ///   - looks: The saved looks; a default one is put in when empty.
    ///   - selection: Which look the page uses, clamped into range.
    init(looks: [TodayStyle], selection: Int) {
        self.looks = looks.isEmpty ? [TodayStyle()] : looks
        self.ids = self.looks.map { _ in UUID() }
        self.selection = min(max(selection, 0), self.looks.count - 1)
    }

    /// The look the page is drawn in.
    var active: TodayStyle { looks[selection] }

    /// One look always stays: the page needs one to show.
    var canRemove: Bool { looks.count > 1 }

    /// Replaces one look with an edited copy.
    ///
    /// - Parameters:
    ///   - look: The edited look.
    ///   - index: Which look to replace; out-of-range does nothing.
    mutating func save(_ look: TodayStyle, at index: Int) {
        guard looks.indices.contains(index) else { return }
        looks[index] = look
    }

    /// Makes one look the page's.
    ///
    /// - Parameter index: Which look; out-of-range does nothing.
    mutating func use(_ index: Int) {
        guard looks.indices.contains(index) else { return }
        selection = index
    }

    /// Adds a look at the end.
    ///
    /// - Parameter look: The look to add.
    mutating func append(_ look: TodayStyle) {
        looks.append(look)
        ids.append(UUID())
    }

    /// Puts a look straight after another and returns where it landed: how
    /// `+` adds one, so the copy sits beside what it was copied from.
    @discardableResult
    mutating func insert(_ look: TodayStyle, after index: Int) -> Int {
        let place = min(max(index + 1, 0), looks.count)
        looks.insert(look, at: place)
        ids.insert(UUID(), at: place)
        if place <= selection { selection += 1 }
        return place
    }

    /// Renames one look.
    ///
    /// - Parameters:
    ///   - name: The new name.
    ///   - index: Which look; out-of-range does nothing.
    mutating func rename(_ name: String, at index: Int) {
        guard looks.indices.contains(index) else { return }
        looks[index].name = name
    }

    /// Puts a removed look back where it was, and the look in use back with
    /// it: how Annulla undoes a delete.
    ///
    /// - Parameters:
    ///   - look: The look that was removed.
    ///   - index: Where it was.
    ///   - selection: Which look was in use before the delete.
    mutating func restore(_ look: TodayStyle, at index: Int, selection: Int, id: UUID = UUID()) {
        let place = min(max(index, 0), looks.count)
        looks.insert(look, at: place)
        ids.insert(id, at: place)
        self.selection = min(max(selection, 0), looks.count - 1)
    }

    /// Removes a look, keeping the one in use where it can; if that is the
    /// one removed, its neighbour takes over.
    @discardableResult
    mutating func remove(at index: Int) -> Bool {
        guard canRemove, looks.indices.contains(index) else { return false }
        looks.remove(at: index)
        ids.remove(at: index)
        if index < selection || selection == looks.count { selection -= 1 }
        selection = min(max(selection, 0), looks.count - 1)
        return true
    }
}


nonisolated extension LookLibrary {
    private nonisolated struct Entry: Codable { let id: UUID; let style: String }
    private nonisolated struct Document: Codable { let version: Int; let entries: [Entry]; let activeID: UUID }

    init?(document: String) {
        guard let data = document.data(using: .utf8),
              let saved = try? JSONDecoder().decode(Document.self, from: data), saved.version == 2,
              !saved.entries.isEmpty, Set(saved.entries.map(\.id)).count == saved.entries.count else { return nil }
        let readable = saved.entries.compactMap { entry in TodayStyle(rawValue: entry.style).map { (entry.id, $0) } }
        guard readable.count == saved.entries.count else { return nil }
        self.init(looks: readable.map(\.1), selection: readable.firstIndex { $0.0 == saved.activeID } ?? 0)
        ids = readable.map(\.0)
    }

    var document: String {
        let entries = zip(ids, looks).map { Entry(id: $0, style: $1.rawValue) }
        let saved = Document(version: 2, entries: entries, activeID: ids[selection])
        guard let data = try? JSONEncoder().encode(saved) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func load(_ defaults: UserDefaults = .standard) -> LookLibrary {
        let stored = defaults.string(forKey: TodayStyle.libraryKey) ?? ""
        if let saved = LookLibrary(document: stored) { return saved }
        let active = defaults.string(forKey: TodayStyle.storageKey).flatMap(TodayStyle.init(rawValue:)) ?? TodayStyle()
        let object = (try? JSONDecoder().decode(JSONValue.self, from: Data(stored.utf8)))?.objectValue
        if object?["version"] != nil || object?["entries"] != nil || stored.range(of: #""(?:version|entries)"\s*:"#, options: .regularExpression) != nil {
            var unavailable = LookLibrary(looks: [active], selection: 0)
            unavailable.canPersist = false
            return unavailable
        }
        return LookLibrary(looks: TodayStyle.library(from: stored, active: active),
                           selection: defaults.integer(forKey: TodayStyle.selectionKey))
    }

    func persist(to defaults: UserDefaults = .standard) {
        guard canPersist else { return }
        defaults.set(document, forKey: TodayStyle.libraryKey)
        defaults.set(selection, forKey: TodayStyle.selectionKey)
    }
}

/// Editing state shared by compact and wide presentations; never applies by itself.
struct LookEditingSession: Equatable {
    var draft: TodayStyle
    let original: TodayStyle
    let index: Int?
    var history = EditHistory()
    var taskSnapshot: TodayStyle?

    func save(in library: inout LookLibrary) -> Int {
        if let index { library.save(draft, at: index); return index }
        library.append(draft)
        return library.looks.count - 1
    }
}
