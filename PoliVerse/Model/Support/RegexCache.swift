import Foundation
import Synchronization

/// Compiled ICU patterns, kept rather than rebuilt on every call.
///
/// The scrapers and text readers would otherwise compile the same handful of
/// patterns hundreds of times over one Manifesti page or one results file.
/// Compiled `NSRegularExpression`s are immutable and safe to share; the cache
/// itself sits behind a `Mutex` because callers run on any thread.
nonisolated enum RegexCache {
    /// A pattern and the options it was compiled with.
    private struct Key: Hashable {
        /// The pattern source.
        let pattern: String
        /// The compile options, as their raw value.
        let options: UInt
    }

    /// How many patterns to keep. Patterns built from page content are not a fixed
    /// set, so beyond this the cache is emptied rather than allowed to grow.
    private static let limit = 256
    /// The compiled patterns, guarded for use from any thread.
    private static let cache = Mutex<[Key: NSRegularExpression]>([:])

    /// The compiled form of a pattern, compiling it on first use.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern.
    ///   - options: Compile options.
    /// - Returns: The compiled expression, or `nil` when the pattern does not compile.
    ///   A failure is not cached.
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
