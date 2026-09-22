import Foundation
import Observation
import OSLog

/// The Politecnico's notifications, as the screens read them.
///
/// The loading belongs to ``Store`` and the endpoint to ``NoticeSource``. What is here
/// is what only this feature knows: the unread count, marking read, and fetching the
/// full text of one notice where the list carried only a summary.
@Observable
@MainActor
final class NoticeModel {
    /// The loaded notices, with their cache and load window.
    private let store: Store<NoticeSource>
    /// Whose notifications to load, and the transport the detail call goes through.
    private let account: any Account
    /// Where “read in PoliVerse” is kept.
    private let readLocally: NoticeSource.ReadState
    /// Diagnostic log for this type, under the `notices` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "notices")

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - account: Whose notifications to load.
    ///   - readLocally: Where read state is kept.
    init(account: any Account, readLocally: NoticeSource.ReadState = .userDefaults) {
        self.account = account
        self.readLocally = readLocally
        var source = NoticeSource()
        source.readLocally = readLocally
        self.store = Store(source, account: account)
    }

    /// The notices, newest first, with their read state resolved.
    var notices: [Notice] { store.value?.notices ?? [] }
    /// Whether the endpoint answered with rows the decoder could not read — a different
    /// thing from an empty inbox, and not to be shown as one.
    var payloadUnreadable: Bool { store.value?.unreadable ?? false }
    /// `true` while a load is in flight.
    var isLoading: Bool { store.isLoading }
    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? { store.errorMessage }
    /// Seconds since the notices were fetched, or `nil` if never.
    var age: TimeInterval? { store.age }

    /// How many notices are unread, which badges the bell.
    var unreadCount: Int { notices.filter { !$0.isRead }.count }

    /// Loads the notifications.
    ///
    /// - Parameter force: Bypasses the store's load window.
    func load(force: Bool = false) async {
        await store.load(force: force)
    }

    /// Fetches one notice's full text, where the list carried only a summary.
    ///
    /// Outside ``Store`` deliberately: one notice fetched on demand, with no load window, no
    /// offline copy and no age. The markup is preserved, since the detail view renders it.
    ///
    /// - Parameter notice: The notice to expand.
    /// - Returns: The full text, or `nil` when the call failed — in which case the list's
    ///   own text stands. Under sample data, the notice's own body.
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

    /// Marks one notice read, on the device and in the held list. Does nothing when it is
    /// already read.
    ///
    /// - Parameter notice: The notice the student opened.
    func markRead(_ notice: Notice) {
        guard !notice.isRead else { return }
        readLocally.insert([notice.id])
        store.update { payload in
            guard let index = payload.notices.firstIndex(where: { $0.id == notice.id })
            else { return }
            payload.notices[index].isRead = true
        }
    }

    /// Marks every held notice read, on the device and in the held list.
    func markAllRead() {
        readLocally.insert(Set(notices.map(\.id)))
        store.update { payload in
            for index in payload.notices.indices { payload.notices[index].isRead = true }
        }
    }
}
