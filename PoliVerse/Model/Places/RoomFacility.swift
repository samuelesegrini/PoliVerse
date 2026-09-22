import Foundation

/// Something a room has: a projector, power at the seats, a piece of software.
///
/// Two public endpoints share one shape, so they share one type:
///
/// ```
/// GET /ricerca/aula/dotazioni/{idaula} → [{"id":4,"it":"Video proiettore","en":"Video projector"}]
/// GET /ricerca/aula/software/{idaula}  → [{"id":348,"it":"Overleaf","en":"Overleaf"}]
/// ```
///
/// Both are unauthenticated, and both answer with an empty array for most rooms —
/// software only for the computer laboratories. An empty list means nothing is
/// recorded rather than that the call failed.
nonisolated struct RoomFacility: Identifiable, Sendable, Hashable, Decodable {
    /// The catalogue's own identifier for this item.
    let id: Int
    /// The Italian name.
    let it: String?
    /// The English name.
    let en: String?

    /// The Italian name, falling back to the English and then to the empty string.
    var name: String { it ?? en ?? "" }

    /// An SF Symbol inferred from the wording.
    ///
    /// The payload carries no icon and its identifiers belong to an internal catalogue,
    /// so the name is matched instead. Decoration only: an unrecognised item still shows,
    /// with a neutral symbol.
    var symbol: String {
        let text = name.lowercased()
        if text.contains("proiettor") || text.contains("projector") { return "videoprojector" }
        if text.contains("microfono") || text.contains("microphone") { return "mic" }
        if text.contains("presa") || text.contains("socket") { return "powerplug" }
        if text.contains("oscurabil") || text.contains("dimmable") { return "sun.max" }
        if text.contains("cattedra") || text.contains("chair") { return "chair" }
        if text.contains("lavagna") || text.contains("board") { return "rectangle.on.rectangle" }
        if text.contains("rete") || text.contains("wifi") || text.contains("network") { return "wifi" }
        if text.contains("video") || text.contains("camera") { return "video" }
        if text.contains("audio") || text.contains("altoparlant") { return "speaker.wave.2" }
        return "checkmark.circle"
    }
}
