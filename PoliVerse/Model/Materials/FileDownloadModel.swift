import Foundation
import Observation
import OSLog

/// Downloads WeBeep files into the app's own storage.
///
/// ## Why not just open the URL
///
/// Moodle authenticates file downloads with the web-service token on the query
/// string (`pluginfile.php?token=…`). Handing that URL to `openURL` opens it in
/// Safari, which puts a long-lived credential into the address bar, the history
/// and any open tab list — somewhere the user cannot easily clear and did not
/// ask for it to go. Fetching it here keeps the token inside the app.
@Observable
final class FileDownloadModel {
    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case downloaded(URL)
        case failed(String)
    }

    private(set) var statuses: [String: Status] = [:]

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "download")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func status(for file: WeBeepFile) -> Status {
        if let known = statuses[file.id] { return known }
        if let existing = existingFile(for: file) { return .downloaded(existing) }
        return .idle
    }

    /// Where a file lives once downloaded.
    ///
    /// Grouped by course so the Files app shows something navigable rather than
    /// one flat heap, and named after the original file.
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

    private func existingFile(for file: WeBeepFile) -> URL? {
        guard let destination = destination(for: file),
              FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

    /// Strips path separators so a server-supplied name cannot escape the
    /// folder it is meant to land in.
    private func sanitised(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "-")
    }

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

    func delete(_ file: WeBeepFile) {
        if let existing = existingFile(for: file) {
            try? FileManager.default.removeItem(at: existing)
        }
        statuses[file.id] = .idle
    }

    /// Bytes held by downloaded materials, for Settings.
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

    static func clearStorage() {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(
            at: base.appendingPathComponent("WeBeep", isDirectory: true))
    }
}
