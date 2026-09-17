import Foundation
import Synchronization

/// Compiled ICU patterns, kept rather than rebuilt on every call.
///
/// The scrapers and text readers compiled their `NSRegularExpression` inside
/// the function that used it, so parsing one Manifesti page or one results
/// file compiled the same handful of patterns hundreds of times. Compiled
/// expressions are immutable and documented as safe to share across threads;
/// the cache itself sits behind a lock because callers run on any of them.
nonisolated enum RegexCache {
    private struct Key: Hashable {
        let pattern: String
        let options: UInt
    }

    /// Patterns built from page content (an escaped course title, say) are
    /// not a fixed set; past this many the cache starts over rather than grow.
    private static let limit = 256
    private static let cache = Mutex<[Key: NSRegularExpression]>([:])

    static func regex(
        _ pattern: String, options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = Key(pattern: pattern, options: options.rawValue)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        cache.withLock { cache in
            if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
            cache[key] = compiled
        }
        return compiled
    }
}
