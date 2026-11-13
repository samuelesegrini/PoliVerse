#if DEBUG && os(iOS)
import SwiftUI

/// The new map's panel background, to compare in the beta (``BetaFeature/newMap``): the
/// system's glass, or a SwiftUI material laid over it with `presentationBackground`.
///
/// Stored under ``storageKey``; a launch argument (`-newMap.sheetMaterial 2`) sets it for
/// screenshots.
enum MapSheetMaterial: Int, CaseIterable, Identifiable {
    /// The system's Liquid Glass: no `presentationBackground`.
    case systemGlass = 0
    /// `.ultraThinMaterial`: the map shows through the most.
    case ultraThin = 1
    /// `.regularMaterial`: in between.
    case regular = 2
    /// `.thickMaterial` with a 6% veil of the accent colour.
    case thickTinted = 3

    static let storageKey = "newMap.sheetMaterial"

    var id: Int { rawValue }

    /// The picker's name, with the API.
    var title: String {
        switch self {
        case .systemGlass: String(localized: "Vetro di sistema")
        case .ultraThin: ".ultraThinMaterial"
        case .regular: ".regularMaterial"
        case .thickTinted: String(localized: ".thickMaterial + tinta")
        }
    }
}

extension View {
    /// The panel's background for a material; nothing for the system glass.
    @ViewBuilder
    func mapSheetMaterial(_ material: MapSheetMaterial) -> some View {
        switch material {
        case .systemGlass: self
        case .ultraThin: presentationBackground(.ultraThinMaterial)
        case .regular: presentationBackground(.regularMaterial)
        case .thickTinted:
            presentationBackground {
                ZStack {
                    Rectangle().fill(.thickMaterial)
                    Color.accentColor.opacity(0.06)
                }
            }
        }
    }
}
#endif
