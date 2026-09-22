import Foundation
import OSLog
import UniformTypeIdentifiers

/// What the app is holding on this device, grouped by what the files actually are.
///
/// The question a student asks when they go looking for space is what is taking it, and
/// for this app the honest answer is a kind of file — four lecture recordings rather
/// than “materials”. So the audit walks the folders the app writes to and groups what it
/// finds the way the Files app would.
///
/// Kinds come from `UTType` rather than a hand-kept list of extensions, so a format
/// nobody thought of still lands in the right group.
nonisolated enum StorageAudit {
    /// Diagnostic log for this type, under the `storage` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "storage")

    /// A group of files, as one row and one segment of the bar.
    struct Category: Identifiable, Sendable, Equatable {
        /// What the files in this group are.
        let kind: Kind
        /// How much space they take.
        let bytes: Int
        /// How many there are.
        let fileCount: Int
        /// What to delete when the row is swiped. Kept so a category can be removed without a
        /// second walk of the disk.
        let urls: [URL]

        /// ``kind``.
        var id: Kind { kind }
    }

    /// The groups files are sorted into. The declared order breaks ties when two groups are
    /// the same size.
    enum Kind: String, Sendable, CaseIterable {
        /// Groups for the files that came from WeBeep, decided by `UTType` conformance.
        case pdf, presentation, document, spreadsheet, video, audio, image, archive, code, other
        /// The app's own JSON — timetables, courses, career — saved so the app opens without a
        /// network. Rebuilt rather than re-downloaded, and removed by its own button.
        case appData

        /// The group's name on screen.
        var title: String {
            switch self {
            case .pdf: String(localized: "PDF")
            case .presentation: String(localized: "Presentazioni")
            case .document: String(localized: "Documenti")
            case .spreadsheet: String(localized: "Fogli di calcolo")
            case .video: String(localized: "Video")
            case .audio: String(localized: "Audio")
            case .image: String(localized: "Immagini")
            case .archive: String(localized: "Archivi")
            case .code: String(localized: "Codice")
            case .other: String(localized: "Altri file")
            case .appData: String(localized: "Dati dell’app")
            }
        }

        /// The SF Symbol for the group.
        var symbol: String {
            switch self {
            case .pdf: "doc.richtext"
            case .presentation: "rectangle.on.rectangle"
            case .document: "doc.text"
            case .spreadsheet: "tablecells"
            case .video: "film"
            case .audio: "waveform"
            case .image: "photo"
            case .archive: "doc.zipper"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .other: "doc"
            case .appData: "internaldrive"
            }
        }

        /// Position in the declared order, for breaking ties by something stabler than a
        /// dictionary's iteration.
        var rank: Int { Kind.allCases.firstIndex(of: self) ?? 0 }

        /// Whether the group came from WeBeep and can be downloaded again.
        var isMaterial: Bool { self != .appData }

        /// Which group a file belongs to, from its extension's `UTType`.
        ///
        /// The order of the checks matters: a Keynote file is both a presentation and a package,
        /// and a CSV is both a spreadsheet and plain text.
        ///
        /// - Parameter url: The file.
        /// - Returns: Its group, and ``Kind/other`` when the extension names no type.
        static func of(_ url: URL) -> Kind {
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                return .other
            }
            // Order matters: a .key is both a presentation and a package, and
            // a .csv is both a spreadsheet and plain text.
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .presentation) { return .presentation }
            if type.conforms(to: .spreadsheet) || type.conforms(to: .commaSeparatedText) { return .spreadsheet }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .archive) { return .archive }
            if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
            if type.conforms(to: .text) || type.conforms(to: .rtf)
                || type.conforms(to: .compositeContent) { return .document }
            return .other
        }
    }

    // MARK: - Reading

    /// Walks the app's folders and groups what it finds, off the main actor.
    ///
    /// A student with a term of recordings has a few hundred files here, and enumerating
    /// them with their sizes is the kind of work that turns a transition into a stutter.
    ///
    /// - Returns: The groups, largest first.
    static func scan() async -> [Category] {
        await Task.detached(priority: .userInitiated) { scanNow() }.value
    }

    /// ``scanNow(materials:appData:)`` over the app's real folders, on the calling thread.
    ///
    /// - Returns: The groups, largest first.
    static func scanNow() -> [Category] {
        scanNow(materials: [materialsDirectory].compactMap(\.self), appData: appDataDirectories)
    }

    /// Walks the given folders and groups what they hold.
    ///
    /// Taking the roots as arguments is what makes this testable: a test lays out a folder
    /// of its own rather than writing into the real Application Support.
    ///
    /// The app's own folders are counted whole as ``Kind/appData``, since a student has no
    /// use for knowing which cache file is which.
    ///
    /// - Parameters:
    ///   - materials: Folders whose contents are grouped by file kind.
    ///   - appData: Folders counted whole.
    /// - Returns: The non-empty groups, largest first, ties broken by ``Kind/rank`` so two
    ///   runs never come back in different orders.
    static func scanNow(materials: [URL], appData: [URL]) -> [Category] {
        var bytes: [Kind: Int] = [:]
        var counts: [Kind: Int] = [:]
        var urls: [Kind: [URL]] = [:]

        for url in materials.flatMap({ files(in: $0) }) {
            let kind = Kind.of(url)
            bytes[kind, default: 0] += size(of: url)
            counts[kind, default: 0] += 1
            urls[kind, default: []].append(url)
        }

        // The caches count as one thing: a student has no use for knowing that
        // the libretto's JSON is 40 kB and the timetable's is 60.
        let own = appData.flatMap { files(in: $0) }
        if !own.isEmpty {
            bytes[.appData] = own.reduce(0) { $0 + size(of: $1) }
            counts[.appData] = own.count
            urls[.appData] = own
        }

        return bytes
            .filter { $0.value > 0 }
            .map { kind, size in
                Category(kind: kind, bytes: size,
                         fileCount: counts[kind] ?? 0, urls: urls[kind] ?? [])
            }
            // Largest first. Ties break on the declared order of ``Kind`` so
            // two runs of the same folder never come back in different orders
            // — a hero icon that swaps on every appearance reads as a bug.
            .sorted {
                $0.bytes == $1.bytes ? $0.kind.rank < $1.kind.rank : $0.bytes > $1.bytes
            }
    }

    // MARK: - Removing

    /// Deletes everything in one group.
    ///
    /// - Parameter category: The group to remove.
    /// - Returns: The bytes actually removed, rather than what was measured: a file the
    ///   system cleared in the meantime is not space this freed.
    @discardableResult
    static func delete(_ category: Category) -> Int {
        var freed = 0
        for url in category.urls {
            let bytes = size(of: url)
            do {
                try FileManager.default.removeItem(at: url)
                freed += bytes
            } catch {
                log.error("Could not remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
            }
        }
        log.notice("Freed \(freed, privacy: .public) bytes from \(category.kind.rawValue, privacy: .public)")
        return freed
    }

    // MARK: - Where things live

    /// The Application Support directory, or `nil` when it cannot be located.
    private static var applicationSupport: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Where ``FileDownloadModel`` saves WeBeep files.
    private static var materialsDirectory: URL? {
        applicationSupport?.appendingPathComponent("WeBeep", isDirectory: true)
    }

    /// The app's own JSON folders: ``DiskCache``'s, ``OfflineStore``'s, and the app group's
    /// copy of the latter, which the widgets read.
    private static var appDataDirectories: [URL] {
        var directories: [URL] = []
        if let support = applicationSupport {
            directories.append(support.appendingPathComponent("PoliVerseCache", isDirectory: true))
            directories.append(support.appendingPathComponent("PoliVerseOffline", isDirectory: true))
        }
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: OfflineStore.groupIdentifier) {
            directories.append(shared.appendingPathComponent("PoliVerseOffline", isDirectory: true))
        }
        return directories
    }

    /// Every regular file under a directory, recursively.
    ///
    /// - Parameter directory: The folder to walk, or `nil`.
    /// - Returns: The files. Empty when the folder is absent or unreadable.
    private static func files(in directory: URL?) -> [URL] {
        guard let directory,
              let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return [] }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            return url
        }
    }

    /// A file's size in bytes.
    ///
    /// - Parameter url: The file.
    /// - Returns: Its size, or zero when it cannot be read.
    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

/// Totals over the groups an audit found.
extension Collection where Element == StorageAudit.Category {
    /// Everything the audit found, in bytes.
    var totalBytes: Int { reduce(0) { $0 + $1.bytes } }

    /// The part that came from WeBeep and can be fetched again, in bytes.
    var materialBytes: Int { lazy.filter(\.kind.isMaterial).reduce(0) { $0 + $1.bytes } }
}
