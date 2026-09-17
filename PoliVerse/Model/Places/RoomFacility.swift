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
/// Both are unauthenticated, and both answer `[]` for most rooms — software
/// only for the computer labs. An empty list is a fact ("nothing recorded"),
/// not a failure.
nonisolated struct RoomFacility: Identifiable, Sendable, Hashable, Decodable {
    let id: Int
    let it: String?
    let en: String?

    /// Italian, since the rest of the UI is, falling back rather than showing
    /// a blank row.
    var name: String { it ?? en ?? "" }

    /// A guess at an SF Symbol from the wording.
    ///
    /// The payload carries no icon and its `id` values are an internal
    /// catalogue we have no key for, so this matches on words instead. It is
    /// decoration: an unrecognised item still shows, with a neutral symbol.
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
