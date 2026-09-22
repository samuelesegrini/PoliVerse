import Foundation
import OSLog

/// The ``Source`` for the Politecnico's notifications.
///
/// `GET {app}/v1/notifications` exists — it appears in the official client and answers
/// 401 unauthenticated — but its body has not been captured, so every field name in
/// ``Notice`` but `id_notice` is a guess. The payload is therefore parsed leniently and
/// its shape is logged in debug builds — keys and types, never values — so that one run
/// on a real account replaces the guesses with fact.
///
/// Read state is layered on in ``adjust(_:)``, which runs on every path.
nonisolated struct NoticeSource: Source {
    /// Names the offline record and the log category.
    static let id = "notices"

    /// Diagnostic log for this type, under the `notices` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "notices")

    /// What one notifications load produces.
    struct Payload: Codable, Sendable, Equatable {
        /// The notices, newest first.
        var notices: [Notice] = []
        /// Whether the endpoint answered with something the decoder could not read.
        ///
        /// Travels with the items rather than being reported as an error, because it is a
        /// different thing from an empty inbox and must not be shown as one.
        var unreadable = false
    }

    /// Where “read in PoliVerse” is kept, used when the payload carries no read flag of its
    /// own.
    ///
    /// Marking read is a write to the university's own system, which this app does not
    /// perform. Injected so a test need not reach into `UserDefaults`.
    var readLocally: ReadState = .userDefaults

    /// Fetches the notifications, newest first.
    ///
    /// - Parameter env: The transport.
    /// - Returns: The notices, flagged unreadable when the payload carried rows the decoder
    ///   could not read.
    /// - Throws: ``APIError``.
    func fetch(_ env: Env) async throws -> Payload {
        let data = try await env.http.data(for: APIRequest(host: .app, path: "/v1/notifications"))
        #if DEBUG
        Self.log.notice("notifications payload shape: \(JSONShape.describe(data), privacy: .public)")
        #endif

        let response = try await BackgroundJSON.decode(NoticesResponse.self, from: data)
        let sorted = response.notices.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
        let unreadable = sorted.isEmpty && !(response.raw.arrayValue?.isEmpty ?? false)
        Self.log.notice("notifications: \(sorted.count, privacy: .public) usable")
        return Payload(notices: sorted, unreadable: unreadable)
    }

    /// The sample notices.
    func sample() -> Payload {
        Payload(notices: Notice.samples())
    }

    /// Resolves each notice's read state.
    ///
    /// The server's own flag wins where it sends one, and a local mark is kept as a floor
    /// either way, so a notice read in the app never reverts to unread on the next fetch.
    ///
    /// - Parameter value: The notices as they arrived, from any of the three origins.
    /// - Returns: The notices with ``Notice/isRead`` set.
    func adjust(_ value: Payload) -> Payload {
        let remembered = readLocally.identifiers()
        var adjusted = value
        adjusted.notices = value.notices.map { notice in
            var updated = notice
            updated.isRead = (notice.serverRead ?? false) || remembered.contains(notice.id)
            return updated
        }
        return adjusted
    }

    /// Where “read in PoliVerse” is kept.
    struct ReadState: Sendable {
        /// The notices marked read on this device.
        var identifiers: @Sendable () -> Set<String>
        /// Records more notices as read.
        var insert: @Sendable (Set<String>) -> Void

        /// Read state kept in `UserDefaults`.
        static let userDefaults = ReadState(
            identifiers: { Set(UserDefaults.standard.stringArray(forKey: "readNotices") ?? []) },
            insert: { added in
                let current = Set(UserDefaults.standard.stringArray(forKey: "readNotices") ?? [])
                UserDefaults.standard.set(Array(current.union(added)), forKey: "readNotices")
            }
        )

        /// Read state that remembers nothing, for tests about the server's own flag.
        static let none = ReadState(identifiers: { [] }, insert: { _ in })
    }
}
