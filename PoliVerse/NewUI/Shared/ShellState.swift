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
    /// The single-page layout is on screen: Oggi without the tab bar, with
    /// the bottom panel.
    var singlePage = false
    var showingProfile = false
    /// Personalizza is open over Oggi.
    #if DEBUG
    /// `-Customize` opens Personalizza at launch, for trying it out.
    var isCustomizing = CommandLine.arguments.contains("-Customize")
    #else
    var isCustomizing = false
    #endif
}

extension ShellState {
    /// One instance for views with no root above them, such as previews of a
    /// single tab. A default built inline would be a new object on every read.
    static let standalone = ShellState()
}

extension EnvironmentValues {
    @Entry var shell: ShellState = .standalone
}
