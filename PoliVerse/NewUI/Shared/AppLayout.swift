import SwiftUI

/// How the app is laid out, chosen by the student in Impostazioni.
enum AppLayout: String, CaseIterable, Identifiable {
    /// Oggi, Corsi, Carriera and Cerca as tabs.
    case tabs
    /// One landing page with everything else in a bottom panel, like Maps.
    case singlePage

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .tabs: "Tab"
        case .singlePage: "Pagina unica"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .tabs: "Oggi, Corsi, Carriera e Cerca in schede separate."
        case .singlePage: "Una sola pagina con il giorno, e tutto il resto in un pannello dal basso."
        }
    }

    var systemImage: String {
        switch self {
        case .tabs: "rectangle.split.3x1"
        case .singlePage: "rectangle.bottomhalf.inset.filled"
        }
    }

    static let storageKey = "appLayout"
}

/// Whether the signed-in app opens the restructured interface or the current
/// tabs. A test switch while the new structure settles.
enum NewInterface {
    static let storageKey = "usesNewInterface"
}
