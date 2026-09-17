import SwiftUI

/// How the app is lit: following the system, always light or dark, or one of
/// two ways of using the Flavor, like Kyo's App Appearance.
nonisolated enum TodayAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    /// Pure white or black behind, cards that stand out.
    case contrast
    /// A clearly coloured page and cards.
    case tinted

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Sistema"
        case .light: "Chiaro"
        case .dark: "Scuro"
        case .contrast: "Contrasto"
        case .tinted: "Tinto"
        }
    }

    /// The scheme the app is held in; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system, .contrast, .tinted: nil
        }
    }

    var flavorMode: Flavor.Mode {
        switch self {
        case .contrast: .contrast
        case .tinted: .tinted
        case .system, .light, .dark: .standard
        }
    }
}

/// The paper the page is printed on, under any decoration: plain, a plotting
/// grid, a sheet with a fibrous grain, or a dotted notebook.
nonisolated enum TodayPaper: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain, plot, paper, dots

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .plain: "Liscia"
        case .plot: "Millimetrata"
        case .paper: "Da disegno"
        case .dots: "Puntinata"
        }
    }
}
