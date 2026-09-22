import Foundation
import Observation

/// The Politecnico's news, as the screens read it.
///
/// The loading belongs to ``Store`` and the endpoint to ``NewsSource``. A type of its
/// own rather than a `Store<NewsSource>` in the environment, so the screens keep asking
/// for the thing they mean.
@Observable
@MainActor
final class NewsModel {
    /// The loaded items, with their cache and load window.
    private let store: Store<NewsSource>

    /// Creates the model.
    ///
    /// - Parameter account: Whose news to load.
    init(account: any Account) {
        self.store = Store(NewsSource(), account: account)
    }

    /// The current items, newest first.
    var items: [NewsItem] { store.value?.items ?? [] }
    /// Whether the endpoint answered with rows the decoder could not read — distinct from
    /// there being no news, and not to be shown as the same.
    var payloadUnreadable: Bool { store.value?.unreadable ?? false }
    /// `true` while a load is in flight.
    var isLoading: Bool { store.isLoading }
    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? { store.errorMessage }
    /// Seconds since the news was fetched, or `nil` if never.
    var age: TimeInterval? { store.age }

    /// The five most recent items, for the Oggi summary.
    var highlights: [NewsItem] { Array(items.prefix(5)) }

    /// Loads the news.
    ///
    /// - Parameter force: Bypasses the store's load window.
    func load(force: Bool = false) async {
        await store.load(force: force)
    }
}
