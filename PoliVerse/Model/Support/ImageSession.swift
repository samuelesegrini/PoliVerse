import Foundation

/// The URL session every `AsyncImage` in the app loads through.
///
/// Installed on the view tree by ``AppShellDuties`` with
/// `asyncImageURLSession(_:)`, so pictures get a cache of their own rather than
/// sharing the small shared-session cache with every API call.
nonisolated enum ImageSession {
    /// A session with a 20 MB in-memory and 150 MB on-disk cache under `Caches/Images`.
    ///
    /// Its request policy is `returnCacheDataElseLoad`, so a stored picture is served
    /// without revalidating: a news photo or an avatar does not change under the same
    /// URL. It does not wait for connectivity, so an offline load fails at once rather
    /// than hanging a row.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024,
                                          diskCapacity: 150 * 1024 * 1024,
                                          directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                                              .first?.appendingPathComponent("Images", isDirectory: true))
        // Serve a stored picture without asking the server first; a news
        // photo or an avatar does not change under the same URL.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}
