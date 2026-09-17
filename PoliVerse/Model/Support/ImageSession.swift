import Foundation

/// The session every `AsyncImage` in the app loads through.
///
/// `AsyncImage` used the shared session, whose cache is small and shared with
/// every API call: a news thumbnail or a profile photo was downloaded again
/// each time its row came back on screen. iOS 27 lets a view tree choose the
/// session (`asyncImageURLSession(_:)`), so images get a cache of their own,
/// sized for pictures and kept on disk across launches.
nonisolated enum ImageSession {
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
