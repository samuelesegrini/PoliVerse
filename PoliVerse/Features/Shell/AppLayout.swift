import SwiftUI

/// How the app is laid out, chosen by the student in Impostazioni.
enum AppLayout: String, CaseIterable, Identifiable {
    /// Oggi, Corsi, Carriera and Cerca as tabs.
    case tabs
    /// One landing page with everything else in a bottom panel, like Maps.
    case singlePage

    /// The layout's identity, which is its raw value.
    var id: String { rawValue }

    /// What the layout is called in Impostazioni.
    var title: LocalizedStringKey {
        switch self {
        case .tabs: "Tab"
        case .singlePage: "Pagina unica"
        }
    }

    /// One line describing what the layout does.
    var detail: LocalizedStringKey {
        switch self {
        case .tabs: "Oggi, Corsi, Carriera e Cerca in schede separate."
        case .singlePage: "Una sola pagina con il giorno, e tutto il resto in un pannello dal basso."
        }
    }

    /// The SF Symbol shown beside the choice.
    var systemImage: String {
        switch self {
        case .tabs: "rectangle.split.3x1"
        case .singlePage: "rectangle.bottomhalf.inset.filled"
        }
    }

    /// The `UserDefaults` key the choice is stored under.
    static let storageKey = "appLayout"
}
