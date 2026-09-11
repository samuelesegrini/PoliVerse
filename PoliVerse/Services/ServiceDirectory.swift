import Foundation
import Observation
import OSLog

/// Where each Politecnico service currently lives.
///
/// ## Why this is fetched rather than hardcoded
///
/// The official web app does not hardcode service hosts. On boot it fetches
/// `/polimi_app/rest/jaf/public/props` — unauthenticated — and reads the base
/// URL of every backend out of it:
///
/// ```json
/// {
///   "iae.base_url":      "https://api.polimi.it/iae",
///   "libretto.base_url": "https://api.polimi.it/piano_studente",
///   "ws_aule.base_url":  "https://api.polimi.it/ws_aule",
///   "maps.base_url":     "https://onlineservices.polimi.it/maps_rest/rest"
/// }
/// ```
///
/// That indirection is exactly why the official app survived the move off
/// `www22.dmz.polimi.it` and PoliFemo did not: PoliFemo baked the old host into
/// a constant in 2023 and still ships it. Reading the same config means a
/// future migration costs us nothing.
///
/// The agenda is the exception — its base is a build-time constant in the
/// official bundle (`REACT_APP_AGENDA_REST_PATH`), not part of `props`.
@Observable
final class ServiceDirectory {
    /// Backends the app talks to.
    nonisolated enum Service: String, CaseIterable, Sendable {
        /// The JAF layer: login, token exchange, user identity.
        case app
        /// Courses, exam sittings, enrolment.
        case iae
        /// Timetable.
        case agenda
        /// Study plan and grade simulation.
        case libretto
        /// WeBeep's Moodle.
        case weBeep

        /// Key in the `props` payload, where one exists.
        var propsKey: String? {
            switch self {
            case .iae: "iae.base_url"
            case .libretto: "libretto.base_url"
            case .app, .agenda, .weBeep: nil
            }
        }

        /// Used until `props` is loaded, and if the fetch fails.
        /// Current as of 2026-09-11.
        var fallback: URL {
            switch self {
            case .app: URL(string: "https://polimiapp.polimi.it/polimi_app/rest")!
            case .iae: URL(string: "https://api.polimi.it/iae")!
            case .agenda: URL(string: "https://api.polimi.it/agenda")!
            case .libretto: URL(string: "https://api.polimi.it/piano_studente")!
            case .weBeep: URL(string: "https://webeep.polimi.it")!
            }
        }
    }

    private(set) var resolved: [Service: URL] = [:]
    private(set) var didLoad = false

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "directory")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func baseURL(for service: Service) -> URL {
        resolved[service] ?? service.fallback
    }

    /// Fetches the service map. Unauthenticated, so it can run before login.
    func load() async {
        guard !didLoad else { return }

        let url = Service.app.fallback.appendingPathComponent("/jaf/public/props")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                log.error("props returned a non-success status; keeping fallbacks")
                didLoad = true
                return
            }

            let props = try JSONDecoder().decode([String: String].self, from: data)
            var map: [Service: URL] = [:]
            for service in Service.allCases {
                guard
                    let key = service.propsKey,
                    let value = props[key],
                    !value.isEmpty,
                    let resolvedURL = URL(string: value)
                else { continue }

                map[service] = resolvedURL
                if resolvedURL != service.fallback {
                    // Worth shouting about: it means a service moved and the
                    // fallback baked into this build is now stale.
                    log.notice("\(service.rawValue, privacy: .public) moved to \(value, privacy: .public)")
                }
            }
            resolved = map
            didLoad = true
            log.info("Service directory loaded (\(map.count) entries)")
        } catch {
            log.error("props fetch failed: \(error.localizedDescription); keeping fallbacks")
            didLoad = true
        }
    }
}
