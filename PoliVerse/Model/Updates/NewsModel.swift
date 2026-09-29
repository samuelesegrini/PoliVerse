import Foundation
import Observation

/// The Politecnico's news, as the screens read it.
///
/// The loading belongs to ``Query`` and the endpoint to ``NewsSource``. A type of its
/// own rather than a `Store<NewsSource>` in the environment, so the screens keep asking
/// for the thing they mean.
@Observable
@MainActor
final class NewsModel {
    /// The loaded items, observed; the loader behind it holds the cache.
    private let query: Query<NewsSource>

    /// Creates the model.
    ///
    /// - Parameter account: Whose news to load.
    init(account: any Account) {
        self.query = Query(NewsSource(), account: account)
    }

    /// The current items, newest first.
    var items: [NewsItem] { query.value?.items ?? [] }
    /// Whether the endpoint answered with rows the decoder could not read — distinct from
    /// there being no news, and not to be shown as the same.
    var payloadUnreadable: Bool { query.value?.unreadable ?? false }
    /// `true` while a load is in flight.
    var isLoading: Bool { query.isLoading }
    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? { query.errorMessage }
    /// Seconds since the news was fetched, or `nil` if never.
    var age: TimeInterval? { query.age }

    /// The five most recent items, for the Oggi summary.
    var highlights: [NewsItem] { Array(items.prefix(5)) }

    /// Loads the news.
    ///
    /// - Parameter force: Fetches even when a fresh value is held; pull-to-refresh.
    func load(force: Bool = false) async {
        await query.load(force: force)
    }
}
