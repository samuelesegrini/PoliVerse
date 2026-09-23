import Foundation

/// The way into recman with the token the app already holds.
///
/// The official app opens the Politecnico's web services from its own session
/// through `POST /jaf/public/linksalto`: it names the service, and the answer is a
/// `jump_url` that signs the browser in. Following that address in
/// ``RecmanBrowser`` reaches the archive with no second sign-in and no single
/// sign-on cookie kept from the app's own login.
///
/// The endpoint checks which services the caller may jump to — a probe for 2428 was
/// refused with `id_servizio` "Unauthorized" (`docs/polimi-api-research.md` §4a) —
/// so a refusal here is expected to be possible, and ``RecordingsModel`` falls back to
/// the recordings' own sign-in. See `docs/recordings.md`.
nonisolated enum RecmanJump {
    /// The archive's service: "Archivio registrazioni didattica". See
    /// ``RecordingsWebKit/entry``.
    static let serviceID = 2314
    /// The service the jump is made from, as the official app names itself.
    static let callerServiceID = "2428"

    /// The body the official app sends, as read from its bundle.
    struct Body: Encodable, Equatable {
        /// The service to land in.
        let targetServiceID: Int
        /// Where the service sends the browser back to.
        let returnURL: String
        /// How the page is to be served.
        let params: Params

        /// The page's parameters.
        struct Params: Encodable, Equatable {
            let lang: String
            /// `DESKTOP`, so the archive comes back as the table ``RecmanParser`` reads.
            let polijDeviceCategory: String
            let polijIntoWebview: Bool
            let alPjMatricola: String?
            let alIdSrvChiamante: String

            enum CodingKeys: String, CodingKey {
                case lang
                case polijDeviceCategory = "polij_device_category"
                case polijIntoWebview = "polij_into_webview"
                case alPjMatricola = "al_pj_matricola"
                case alIdSrvChiamante = "al_id_srv_chiamante"
            }
        }

        enum CodingKeys: String, CodingKey {
            case targetServiceID = "target_service_id"
            case returnURL = "return_url"
            case params
        }
    }

    /// The answer: where to send the browser.
    struct Answer: Decodable {
        /// The signed-in address of the service.
        let jumpURL: String?

        enum CodingKeys: String, CodingKey {
            case jumpURL = "jump_url"
        }

        /// ``jumpURL`` as a URL, when it is one.
        var url: URL? { jumpURL.flatMap(URL.init(string:)) }
    }

    /// The body for a jump into recman.
    ///
    /// - Parameter matricola: The signed-in matricola, which the official app sends
    ///   along.
    /// - Returns: The body.
    static func body(matricola: String?) -> Body {
        Body(
            targetServiceID: serviceID,
            returnURL: RecordingsWebKit.entry.absoluteString,
            params: .init(
                lang: PoliMiLanguage.current.lowercased,
                polijDeviceCategory: "DESKTOP",
                polijIntoWebview: false,
                alPjMatricola: matricola,
                alIdSrvChiamante: callerServiceID))
    }

    /// The request, sent with the app's token.
    ///
    /// - Parameter matricola: The signed-in matricola.
    /// - Returns: The request.
    static func request(matricola: String?) -> APIRequest {
        APIRequest(
            host: .app,
            path: "/jaf/public/linksalto",
            method: "POST",
            body: try? JSONEncoder().encode(body(matricola: matricola)))
    }
}
