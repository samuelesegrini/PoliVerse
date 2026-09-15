import SwiftUI

/// State that must outlive a change of layout: the day being shown and the
/// sheets open over the app.
///
/// Owned by ``NewRootView`` above both layouts. Presented from a layout
/// instead, switching tabs ↔ pagina unica from Impostazioni tore down the
/// view that owned the sheet, closing it mid-change.
@MainActor @Observable
final class ShellState {
    /// Where the Personalizza transition is: the app at full size, shrunk to
    /// a card, or replaced by the gallery whose middle card sits exactly
    /// where the shrunk app was.
    enum CustomizeStage { case off, shrunk, gallery }
    #if DEBUG
    var customizeStage: CustomizeStage = CommandLine.arguments.contains("-Customize") ? .gallery
        : CommandLine.arguments.contains("-CustomizeShrunk") ? .shrunk : .off
    #else
    var customizeStage = CustomizeStage.off
    #endif

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

    /// The day stepper popover under the date.
    var showingDays = false

    // MARK: Single-page panel

    enum PanelDetent: Hashable { case peek, half, full }
    var panelDetent = PanelDetent.peek
    /// Something asked to present while the panel was up; it runs once the
    /// panel's sheet has gone, since one view presents one thing at a time.
    private(set) var pendingPresentation: (() -> Void)?
    private var panelHeld = false

    /// The panel is presented only while nothing else is.
    var showsPanel: Bool {
        singlePage && !panelHeld && pendingPresentation == nil && !showingSettings && !showingProfile
            && !showingDays && !isCustomizing && customizeStage == .off
    }

    /// Opens a sheet, popover or Personalizza: straight away in the tab
    /// layout, after the panel steps aside in the single page.
    func present(_ action: @escaping () -> Void) {
        guard singlePage, showsPanel else { action(); return }
        pendingPresentation = action
    }

    /// Called when the panel's sheet has finished dismissing.
    func panelDidDismiss() {
        guard let action = pendingPresentation else { return }
        panelHeld = true
        pendingPresentation = nil
        action()
        panelHeld = false
    }
}

extension ShellState {
    /// One instance for views with no root above them, such as previews of a
    /// single tab. A default built inline would be a new object on every read.
    static let standalone = ShellState()
}

extension EnvironmentValues {
    @Entry var shell: ShellState = .standalone
}
