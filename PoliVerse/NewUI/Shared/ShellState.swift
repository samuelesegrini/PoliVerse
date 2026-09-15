import SwiftUI

/// State that must outlive a change of layout: the day being shown and the
/// sheets open over the app.
///
/// Owned by ``NewRootView`` above both layouts. Presented from a layout
/// instead, switching tabs ↔ pagina unica from Impostazioni tore down the
/// view that owned the sheet, closing it mid-change.
@MainActor @Observable
final class ShellState {
    var day = Date.now
    var showingSettings = false
    var showingProfile = false
}

extension EnvironmentValues {
    /// A throwaway default keeps previews of single tabs working without a
    /// root above them.
    @Entry var shell = ShellState()
}
