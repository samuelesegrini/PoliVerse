import Testing
import Foundation
@testable import PoliVerse

/// The official web app resolves every backend through
/// `/polimi_app/rest/jaf/public/props` instead of hardcoding hosts. That is why
/// it survived `www22.dmz.polimi.it/iae` becoming `api.polimi.it/iae` and
/// PoliFemo — which baked the old host into a constant in 2023 — did not.
@Suite("Service directory")
@MainActor
struct ServiceDirectoryTests {
    @Test("Before loading, every service falls back to a usable base")
    func fallbacksUsableImmediately() {
        let directory = ServiceDirectory()
        for service in ServiceDirectory.Service.allCases {
            let url = directory.baseURL(for: service)
            #expect(url.scheme == "https", "\(service.rawValue) must be https")
            #expect(url.host?.isEmpty == false)
        }
    }

    /// The fallbacks are what ship in the binary, so a regression here means
    /// shipping a build that talks to a host that no longer answers.
    @Test("Fallbacks point at the hosts verified live on 2026-09-11")
    func fallbacksMatchVerifiedHosts() {
        let directory = ServiceDirectory()
        #expect(directory.baseURL(for: .iae).absoluteString
                == "https://api.polimi.it/iae")
        #expect(directory.baseURL(for: .agenda).absoluteString
                == "https://api.polimi.it/agenda")
        #expect(directory.baseURL(for: .libretto).absoluteString
                == "https://api.polimi.it/piano_studente")
        #expect(directory.baseURL(for: .app).absoluteString
                == "https://polimiapp.polimi.it/polimi_app/rest")

        // The host PoliFemo still ships. If this ever becomes a fallback again,
        // something has gone badly wrong.
        for service in ServiceDirectory.Service.allCases {
            #expect(directory.baseURL(for: service).host != "www22.dmz.polimi.it")
        }
    }

    @Test("Only services that appear in props carry a key")
    func propsKeysAreCorrect() {
        #expect(ServiceDirectory.Service.iae.propsKey == "iae.base_url")
        #expect(ServiceDirectory.Service.libretto.propsKey == "libretto.base_url")
        // The agenda base is a build-time constant in the official bundle
        // (REACT_APP_AGENDA_REST_PATH), not part of props.
        #expect(ServiceDirectory.Service.agenda.propsKey == nil)
        #expect(ServiceDirectory.Service.app.propsKey == nil)
        #expect(ServiceDirectory.Service.weBeep.propsKey == nil)
    }

    /// `props` is a flat string map; decoding it as anything richer would break
    /// on the empty values it contains (`"piani.base_url": ""`).
    @Test("A props payload shaped like the real one decodes")
    func decodesRealisticProps() throws {
        let payload = """
        {"maps.base_url":"https://onlineservices.polimi.it/maps_rest/rest",\
        "piani.base_url":"","piani.profile":"","libretto.profile":"0",\
        "libretto.base_url":"https://api.polimi.it/piano_studente",\
        "iae.profile":"0","iae.base_url":"https://api.polimi.it/iae"}
        """
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))

        #expect(decoded["iae.base_url"] == "https://api.polimi.it/iae")
        #expect(decoded["libretto.base_url"] == "https://api.polimi.it/piano_studente")
        // Empty values must be ignored rather than becoming a base URL of "".
        #expect(decoded["piani.base_url"] == "")
    }
}
