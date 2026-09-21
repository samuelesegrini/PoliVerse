import Foundation
import OSLog

/// Notifications from the Politecnico.
///
/// `GET {app}/v1/notifications` is present in the official bundle's own client
/// and answers 401 unauthenticated, so it exists — but its body was never
/// captured, and every field name in ``Notice`` is a guess apart from
/// `id_notice`. So the payload is parsed leniently, and its *shape* is logged —
/// keys and types, never values — so one run on a real account replaces the
/// guesses with fact.
nonisolated struct NoticeSource: Source {
    static let id = "notices"

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "notices")

    /// See ``NewsSource/Payload`` for why `unreadable` travels with the items.
    struct Payload: Codable, Sendable, Equatable {
        var notices: [Notice] = []
        var unreadable = false
    }

    /// Read state this device remembers, used when the payload carries no read
    /// flag of its own.
    ///
    /// Marking read is a write to the real university system, which this app
    /// does not do — so "read" here means "read in PoliVerse". Injected so a
    /// test does not have to reach into `UserDefaults`.
    var readLocally: ReadState = .userDefaults

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

    func sample() -> Payload {
        Payload(notices: Notice.samples())
    }

    /// The server's own flag wins where it sends one; otherwise this device
    /// remembers. Local marks are kept as a floor either way, so a notice read
    /// here never reverts to unread on the next fetch.
    ///
    /// Applied on every path — fetched, cached and sample alike — which is the
    /// whole reason ``Source/adjust(_:)`` exists.
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

    /// Where "read in PoliVerse" is kept.
    struct ReadState: Sendable {
        var identifiers: @Sendable () -> Set<String>
        var insert: @Sendable (Set<String>) -> Void

        static let userDefaults = ReadState(
            identifiers: { Set(UserDefaults.standard.stringArray(forKey: "readNotices") ?? []) },
            insert: { added in
                let current = Set(UserDefaults.standard.stringArray(forKey: "readNotices") ?? [])
                UserDefaults.standard.set(Array(current.union(added)), forKey: "readNotices")
            }
        )

        /// Remembers nothing, for tests about the server's own flag.
        static let none = ReadState(identifiers: { [] }, insert: { _ in })
    }
}
