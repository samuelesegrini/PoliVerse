import Foundation
import Observation
import OSLog

/// Notifications from the Politecnico.
///
/// `GET {app}/v1/notifications` is present in the official bundle's own client
/// and answers 401 unauthenticated, so it exists — but its body was never
/// captured, and every field name in ``Notice`` is a guess apart from
/// `id_notice`.
///
/// Two consequences, both deliberate:
///
/// - the payload is parsed leniently, so a wrong guess costs a field rather
///   than the whole screen;
/// - the payload's *shape* is logged — keys and types, never values — so one
///   run on a real account replaces the guesses with fact.
@Observable
final class NoticeService {
    private(set) var notices: [Notice] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Set when the endpoint answers but carries nothing this decoder could
    /// read, which is a different thing from an empty inbox and must not be
    /// shown as one.
    private(set) var payloadUnreadable = false

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "notices")
    private var window = LoadWindow()

    /// Identifies the data currently held, so a change of account — or of the
    /// sample-data toggle — always reloads instead of waiting out the window.
    private var source: String {
        session.useMockData ? "mock" : (session.student?.matricola ?? "anonymous")
    }

    /// Read state this device remembers, used when the payload carries no read
    /// flag of its own. Marking read is a write to the real university system,
    /// which this app does not do — so "read" here means "read in PoliVerse".
    private var readLocally: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "readNotices") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "readNotices") }
    }

    var unreadCount: Int { notices.filter { !$0.isRead }.count }

    init(session: Session) {
        self.session = session
    }

    func load(force: Bool = false) async {
        guard !isLoading, window.shouldLoad(force: force, source: source) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if session.useMockData {
            notices = applyReadState(MockData.notices())
            payloadUnreadable = false
            window.markLoaded(source: source)
            return
        }

        do {
            // Fetched as raw bytes first: the shape log is the whole point of
            // this call on its first run, and it has to survive a decode that
            // reads nothing.
            let data = try await session.api.send(APIRequest(host: .app, path: "/v1/notifications"))
            log.notice("notifications payload shape: \(JSONShape.describe(data), privacy: .public)")

            let response = try JSONDecoder().decode(NoticesResponse.self, from: data)
            notices = applyReadState(response.notices).sorted {
                ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            // An empty array is an empty inbox; an unreadable body is a bug.
            payloadUnreadable = notices.isEmpty && !(response.raw.arrayValue?.isEmpty ?? false)
            log.notice("notifications: \(self.notices.count, privacy: .public) usable, \(self.unreadCount, privacy: .public) unread")
            window.markLoaded(source: source)
        } catch let error as APIError {
            // A withdrawn endpoint is worth saying plainly rather than as a
            // generic failure — it means this feature is gone, not broken.
            if case .endpointGone = error {
                log.error("Notifications endpoint is gone")
            }
            errorMessage = error.localizedDescription
        } catch {
            log.error("Notifications failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the full text of one notice, where the list only carried a
    /// summary. Returns nil when the detail call fails; the list text stands.
    func detail(for notice: Notice) async -> String? {
        guard !session.useMockData else { return notice.body }
        do {
            let data = try await session.api.send(
                APIRequest(host: .app, path: "/v1/notifications/\(notice.id)"))
            log.notice("notification detail shape: \(JSONShape.describe(data), privacy: .public)")
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            guard let fields = value.objectValue else { return nil }
            // Raw: the detail view renders it, so the markup has to survive
            // the trip.
            return fields.firstValue([
                "body", "testo", "text", "messaggio", "message", "contenuto",
                "content", "descrizione_estesa", "html", "descrizione",
            ]).flatMap(Notice.rawText(from:))
        } catch {
            log.error("Notification detail failed: \(error.localizedDescription)")
            return nil
        }
    }

    func markRead(_ notice: Notice) {
        guard !notice.isRead else { return }
        var current = readLocally
        current.insert(notice.id)
        readLocally = current
        apply(to: notice) { $0.isRead = true }
    }

    func markAllRead() {
        readLocally = readLocally.union(notices.map(\.id))
        notices = notices.map { notice in
            var updated = notice
            updated.isRead = true
            return updated
        }
    }

    /// The server's own flag wins where it sends one; otherwise this device
    /// remembers. Local marks are kept as a floor either way, so a notice read
    /// here never reverts to unread on the next fetch.
    private func applyReadState(_ loaded: [Notice]) -> [Notice] {
        let remembered = readLocally
        return loaded.map { notice in
            var updated = notice
            updated.isRead = (notice.serverRead ?? false) || remembered.contains(notice.id)
            return updated
        }
    }

    private func apply(to notice: Notice, _ change: (inout Notice) -> Void) {
        guard let index = notices.firstIndex(where: { $0.id == notice.id }) else { return }
        change(&notices[index])
    }
}
