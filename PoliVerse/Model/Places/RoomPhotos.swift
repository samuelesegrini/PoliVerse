import Foundation
import OSLog

/// The rooms' photos, from the Politecnico's public maps service.
///
/// Two requests stand between a room and its picture, neither needing a token:
/// `/spazi/aula` lists every room with an `idfoto` ("0" when there is none), and
/// `/syncro/rooms/foto/{idfoto}` answers with a plain-text signed link on
/// docmanager.polimi.it, which serves the JPEG. The index is read once per launch; the
/// pictures are kept on disk by `idfoto`, because the signed link changes every time.
///
/// Nothing waits on a photo: the room card shows the map first, and offers the photo once
/// its id is known.
actor RoomPhotos {
    /// The one store the app shares.
    static let shared = RoomPhotos()

    /// The maps service's base URL.
    private static let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    private let session: URLSession
    private let folder: URL?
    /// `csiv` → `idfoto`, once read.
    private var index: [String: String]?
    /// The read of the index in flight, shared by everyone who asks meanwhile.
    private var indexTask: Task<[String: String], Never>?
    /// Pictures already decoded this launch, by `idfoto`.
    private var memory: [String: Data] = [:]
    /// Downloads in flight, by `idfoto`.
    private var downloads: [String: Task<Data?, Never>] = [:]

    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "room-photos")

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - session: The session requests go through.
    ///   - folder: Where pictures are kept; the caches folder by default.
    init(session: URLSession = .shared, folder: URL? = nil) {
        self.session = session
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "RoomPhotos", directoryHint: .isDirectory)
    }

    // MARK: - Parsing

    /// `csiv` → `idfoto` out of the `/spazi/aula` payload, leaving out the rooms whose
    /// `idfoto` is "0", empty or missing.
    ///
    /// - Parameter data: The payload: a JSON array of rooms.
    /// - Returns: The rooms with a photo; empty when the payload cannot be read.
    nonisolated static func index(from data: Data) -> [String: String] {
        guard let rows = try? JSONDecoder().decode([RoomPhotoRow].self, from: data) else { return [:] }
        var index: [String: String] = [:]
        for row in rows {
            guard let csiv = row.csiv?.trimmingCharacters(in: .whitespaces), !csiv.isEmpty,
                  let photo = row.idfoto?.trimmingCharacters(in: .whitespaces),
                  !photo.isEmpty, photo != "0", Int(photo) != nil
            else { continue }
            index[csiv] = photo
        }
        return index
    }

    /// The signed link out of `/syncro/rooms/foto/{idfoto}`'s body.
    ///
    /// The body is the link as plain text, sometimes with a newline or in quotes.
    ///
    /// - Parameter body: The response body.
    /// - Returns: The link, or `nil` unless it is an https URL.
    nonisolated static func signedURL(from body: Data) -> URL? {
        guard var text = String(data: body, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }

    /// The link that answers with a photo's signed link.
    nonisolated static func linkURL(for photoID: String) -> URL {
        base.appending(path: "syncro/rooms/foto").appending(path: photoID)
    }

    // MARK: - Reading

    /// The photo id of a room, reading the index the first time it is asked.
    ///
    /// - Parameter roomCode: The room's `csiv` (``Classroom/roomCode``).
    /// - Returns: The `idfoto`, or `nil` when the room has none or the index cannot be read.
    func photoID(for roomCode: String?) async -> String? {
        guard let roomCode, !roomCode.isEmpty else { return nil }
        return await loadIndex()[roomCode]
    }

    /// Whether the index has been read, so that "no photo" can be told from "not yet known".
    func photoIDIfKnown(for roomCode: String?) -> (known: Bool, id: String?) {
        guard let index else { return (false, nil) }
        guard let roomCode else { return (true, nil) }
        return (true, index[roomCode])
    }

    private func loadIndex() async -> [String: String] {
        if let index { return index }
        if let indexTask { return await indexTask.value }
        let session = session
        let url = Self.base.appending(path: "spazi/aula")
        let task = Task<[String: String], Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400
            else { return [:] }
            return Self.index(from: data)
        }
        indexTask = task
        let value = await task.value
        indexTask = nil
        // An index that failed to read is tried again next time, rather than every room
        // being reported without a photo for the rest of the launch.
        if !value.isEmpty { index = value }
        log.notice("room photos: \(value.count, privacy: .public) rooms with a photo")
        return value
    }

    /// A photo's JPEG, from memory, from disk, or downloaded and kept.
    ///
    /// - Parameter photoID: The `idfoto`.
    /// - Returns: The image data, or `nil` when it cannot be fetched.
    func imageData(for photoID: String) async -> Data? {
        if let data = memory[photoID] { return data }
        let file = folder?.appending(path: "\(photoID).jpg")
        if let file, let data = try? Data(contentsOf: file), !data.isEmpty {
            memory[photoID] = data
            return data
        }
        if let task = downloads[photoID] { return await task.value }
        let session = session
        let task = Task<Data?, Never> {
            guard let (body, _) = try? await session.data(from: Self.linkURL(for: photoID)),
                  let signed = Self.signedURL(from: body),
                  let (data, response) = try? await session.data(from: signed),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  !data.isEmpty
            else { return nil }
            return data
        }
        downloads[photoID] = task
        let data = await task.value
        downloads[photoID] = nil
        guard let data else { return nil }
        memory[photoID] = data
        if let folder, let file {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return data
    }
}

/// One row of `/spazi/aula`, as far as the photos need it.
nonisolated private struct RoomPhotoRow: Decodable {
    /// The room's space code.
    let csiv: String?
    /// The photo's id, "0" when there is none.
    let idfoto: String?
}
