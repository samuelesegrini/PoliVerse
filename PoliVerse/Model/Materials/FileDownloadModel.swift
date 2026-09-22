import Foundation
import Observation
import OSLog

/// Downloads WeBeep files into the app's own storage.
///
/// Moodle authenticates downloads with the web-service token on the query string, so
/// handing such an address to the system would open it in Safari and put a long-lived
/// credential into the address bar, the history and the tab list. Fetching the file
/// here keeps the token inside the app.
///
/// Files land under `Application Support/WeBeep/<course>/<name>`, excluded from
/// backup since course material can be downloaded again.
@Observable
final class FileDownloadModel {
    /// Where one file's download has got to.
    enum Status: Equatable {
        /// Not downloaded, and nothing in flight.
        case idle
        /// In flight, with the fraction complete.
        case downloading(progress: Double)
        /// On the device, at this location.
        case downloaded(URL)
        /// The download did not complete, with a sentence explaining why.
        case failed(String)
    }

    /// The known status per ``WeBeepFile/id``.
    private(set) var statuses: [String: Status] = [:]

    /// Diagnostic log for this type, under the `download` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "download")
    /// The session downloads are issued through.
    private let session: URLSession

    /// Creates the model.
    ///
    /// - Parameter session: The session downloads are issued through.
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A file's status, checking the filesystem when nothing is recorded.
    ///
    /// - Parameter file: The file to ask about.
    /// - Returns: The recorded status, ``Status/downloaded(_:)`` when a copy exists on
    ///   disk, and ``Status/idle`` otherwise.
    func status(for file: WeBeepFile) -> Status {
        if let known = statuses[file.id] { return known }
        if let existing = existingFile(for: file) { return .downloaded(existing) }
        return .idle
    }

    /// Where a file lives once downloaded, creating the folder if needed.
    ///
    /// Grouped by course, so the Files app shows something navigable rather than one flat
    /// heap, and named after the original file.
    ///
    /// - Parameter file: The file.
    /// - Returns: The location, or `nil` when Application Support cannot be located.
    private func destination(for file: WeBeepFile) -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        let folder = base
            .appendingPathComponent("WeBeep", isDirectory: true)
            .appendingPathComponent(sanitised(file.courseID), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(sanitised(file.name))
    }

    /// The file's location if a copy is already on the device.
    ///
    /// - Parameter file: The file.
    /// - Returns: The location, or `nil` when there is no copy.
    private func existingFile(for file: WeBeepFile) -> URL? {
        guard let destination = destination(for: file),
              FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

    /// Strips path separators and parent references, so a server-supplied name cannot
    /// escape the folder it is meant to land in.
    ///
    /// - Parameter name: The name as WeBeep sent it.
    /// - Returns: The safe name.
    private func sanitised(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "-")
    }

    /// Downloads a file, or returns the copy already on the device.
    ///
    /// A non-2xx status, and an HTML body where HTML is not expected — which is how Moodle
    /// reports an expired token, with a 200 — both fail rather than saving something that
    /// would later refuse to open. The saved file is excluded from backup.
    ///
    /// - Parameter file: The file to fetch.
    /// - Returns: Where the file is, or `nil` when it has no address, a download is
    ///   already in flight, or the download failed.
    @discardableResult
    func download(_ file: WeBeepFile) async -> URL? {
        if let existing = existingFile(for: file) {
            statuses[file.id] = .downloaded(existing)
            return existing
        }
        guard let source = file.downloadURL, let destination = destination(for: file) else {
            statuses[file.id] = .failed("Nessun collegamento per questo file.")
            return nil
        }
        if case .downloading = status(for: file) { return nil }

        statuses[file.id] = .downloading(progress: 0)
        do {
            let (temporary, response) = try await session.download(from: source)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                statuses[file.id] = .failed("WeBeep ha risposto \(http.statusCode).")
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }

            // Moodle answers an expired token with an HTML error page and a
            // 200, so a short "file" that is really markup would otherwise be
            // saved and later fail to open with no explanation.
            if let type = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type"),
               type.contains("text/html"), file.fileExtension != "html" {
                statuses[file.id] = .failed("La sessione WeBeep è scaduta.")
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)

            // Course material is re-downloadable; excluding it keeps iCloud
            // backups small and avoids a rejection for backing up caches.
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutable = destination
            try? mutable.setResourceValues(resourceValues)

            statuses[file.id] = .downloaded(destination)
            log.info("Downloaded \(file.name, privacy: .public)")
            return destination
        } catch {
            log.error("Download failed: \(error.localizedDescription)")
            statuses[file.id] = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Removes the downloaded copy and returns the file to ``Status/idle``.
    ///
    /// - Parameter file: The file to remove.
    func delete(_ file: WeBeepFile) {
        if let existing = existingFile(for: file) {
            try? FileManager.default.removeItem(at: existing)
        }
        statuses[file.id] = .idle
    }

    /// Total size of the downloaded materials, in bytes, as Impostazioni reports it. Zero
    /// when nothing has been downloaded.
    static func storageInBytes() -> Int {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return 0 }
        let root = base.appendingPathComponent("WeBeep", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    /// Removes every downloaded file.
    static func clearStorage() {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(
            at: base.appendingPathComponent("WeBeep", isDirectory: true))
    }
}
