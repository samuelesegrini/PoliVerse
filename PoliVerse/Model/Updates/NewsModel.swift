import Foundation
import Observation

/// News from the Politecnico, as the screens read it.
///
/// The loading is ``Store``'s and the endpoint is ``NewsSource``'s; what is
/// left here is the handful of things only this feature knows — chiefly which
/// items the Home summary shows. Kept as a type of its own rather than putting
/// `Store<NewsSource>` in the environment, so the screens keep asking for the
/// thing they mean.
@Observable
@MainActor
final class NewsModel {
    private let store: Store<NewsSource>

    init(account: any Account) {
        self.store = Store(NewsSource(), account: account)
    }

    var items: [NewsItem] { store.value?.items ?? [] }
    /// The endpoint answered with something the decoder could not read —
    /// distinct from there being no news, and not to be shown as the same.
    var payloadUnreadable: Bool { store.value?.unreadable ?? false }
    var isLoading: Bool { store.isLoading }
    var errorMessage: String? { store.errorMessage }
    var age: TimeInterval? { store.age }

    /// The few most recent items, for the Home summary.
    var highlights: [NewsItem] { Array(items.prefix(5)) }

    func load(force: Bool = false) async {
        await store.load(force: force)
    }
}
