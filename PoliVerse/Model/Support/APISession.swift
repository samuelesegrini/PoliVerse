import Foundation

/// The URL session the Politecnico's services and WeBeep are called through.
///
/// `api.polimi.it` and `webeep.polimi.it` answer over HTTP/1.1, one request per
/// connection at a time, and `URLSession.shared` opens at most four connections to a
/// host on iOS. The refresh at launch sends about nine requests to `api.polimi.it` at
/// once — the career's five, the timetable's two, the news, the teachings — so under
/// the shared session half of them waited for a connection to come free before
/// leaving the phone. Eight lets one launch's requests leave together, which is still
/// fewer than a browser opens to a site with its pictures.
nonisolated enum APISession {
    /// Connections per host.
    static let connectionsPerHost = 8

    /// A default session, with the shared URL cache and eight connections per host.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = connectionsPerHost
        return URLSession(configuration: configuration)
    }()
}
