import Foundation
import Observation
import OSLog

/// Notifications from the Politecnico, as the screens read it.
///
/// The loading is ``Store``'s and the endpoint is ``NoticeSource``'s. What is
/// left here is what only this feature knows: the unread count, marking read,
/// and fetching the full text of one notice where the list carried a summary.
@Observable
@MainActor
final class NoticeModel {
    private let store: Store<NoticeSource>
    private let account: any Account
    private let readLocally: NoticeSource.ReadState
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "notices")

    init(account: any Account, readLocally: NoticeSource.ReadState = .userDefaults) {
        self.account = account
        self.readLocally = readLocally
        var source = NoticeSource()
        source.readLocally = readLocally
        self.store = Store(source, account: account)
    }

    var notices: [Notice] { store.value?.notices ?? [] }
    /// The endpoint answered but carried nothing the decoder could read, which
    /// is a different thing from an empty inbox and must not be shown as one.
    var payloadUnreadable: Bool { store.value?.unreadable ?? false }
    var isLoading: Bool { store.isLoading }
    var errorMessage: String? { store.errorMessage }
    var age: TimeInterval? { store.age }

    var unreadCount: Int { notices.filter { !$0.isRead }.count }

    func load(force: Bool = false) async {
        await store.load(force: force)
    }

    /// Fetches the full text of one notice, where the list only carried a
    /// summary. Returns nil when the detail call fails; the list text stands.
    ///
    /// Outside ``Store`` deliberately: it is one notice fetched on demand, with
    /// no window, no offline copy and no age — none of the pipeline applies.
    func detail(for notice: Notice) async -> String? {
        guard !account.isSample else { return notice.body }
        do {
            let data = try await account.http.data(
                for: APIRequest(host: .app, path: "/v1/notifications/\(notice.id)"))
            #if DEBUG
            log.notice("notification detail shape: \(JSONShape.describe(data), privacy: .public)")
            #endif
            let value = try await BackgroundJSON.decode(JSONValue.self, from: data)
            guard let fields = value.objectValue else { return nil }
            // Raw: the detail view renders it, so the markup has to survive the
            // trip.
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
        readLocally.insert([notice.id])
        store.update { payload in
            guard let index = payload.notices.firstIndex(where: { $0.id == notice.id })
            else { return }
            payload.notices[index].isRead = true
        }
    }

    func markAllRead() {
        readLocally.insert(Set(notices.map(\.id)))
        store.update { payload in
            for index in payload.notices.indices { payload.notices[index].isRead = true }
        }
    }
}
