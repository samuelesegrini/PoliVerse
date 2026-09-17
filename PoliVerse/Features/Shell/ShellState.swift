import SwiftUI

/// State that must outlive a change of layout: the day being shown, where
/// each layout is, and the sheets open over the app.
///
/// Owned by ``NewRootView`` above both layouts. Presented from a layout
/// instead, switching tabs ↔ pagina unica from Impostazioni tore down the
/// view that owned the sheet, closing it mid-change.
@MainActor @Observable
final class ShellState {
    var day = Date.now
    /// The tab on screen in the tab layout.
    #if DEBUG
    /// `-Tab courses` opens a tab at launch, for trying it out.
    var selection = UserDefaults.standard.string(forKey: "Tab").flatMap(NewDestination.Tab.init(rawValue:)) ?? .today
    #else
    var selection = NewDestination.Tab.today
    #endif
    /// Cerca's pushed screens, so a way in from outside can open a place.
    /// Untyped: the screens pushed further in push courses and teachers.
    var searchPath = NavigationPath()
    var showingSettings = false
    /// Impostazioni's pushed pages; the profile opens it one page in.
    var settingsPath: [SettingsPage] = []
    /// The single-page layout is on screen: Oggi without the tab bar, with
    /// the bottom panel.
    var singlePage = false
    /// Personalizza is open over Oggi.
    #if DEBUG
    /// `-Customize` opens Personalizza at launch, for trying it out.
    var isCustomizing = CommandLine.arguments.contains("-Customize")
    #else
    var isCustomizing = false
    #endif

    /// The day stepper popover under the date.
    var showingDays = false
    /// The lesson or sitting an Oggi row opened.
    var detail: TodayDetail?

    enum SettingsPage: Hashable { case profile }

    /// Impostazioni, opened on the profile.
    func openProfile() {
        present {
            self.settingsPath = [.profile]
            self.showingSettings = true
        }
    }

    // MARK: Single-page panel

    enum PanelDetent: Hashable { case peek, half, full }
    var panelDetent = PanelDetent.peek
    /// The panel's pushed screens. Kept here, not in the panel, because the
    /// panel's sheet goes away whenever something else is presented.
    var panelPath = NavigationPath()
    /// The panel's sheet has appeared and not yet gone.
    var panelIsOnScreen = false
    /// Something asked to present while the panel was up; it runs once the
    /// panel's sheet has gone, since one view presents one thing at a time.
    private(set) var pendingPresentation: (() -> Void)?
    private var panelHeld = false

    /// The panel is presented only while nothing else is.
    var showsPanel: Bool {
        singlePage && !panelHeld && pendingPresentation == nil && !showingSettings
            && !showingDays && !isCustomizing && detail == nil
    }

    /// Opens a sheet, popover or Personalizza: straight away in the tab
    /// layout, after the panel steps aside in the single page.
    ///
    /// Only a panel actually on screen defers: one still on its way, as while
    /// the layouts animate, would never report its dismissal.
    func present(_ action: @escaping () -> Void) {
        guard singlePage, showsPanel, panelIsOnScreen else { action(); return }
        pendingPresentation = action
    }

    /// Called when the panel's sheet has finished dismissing.
    func panelDidDismiss() {
        panelIsOnScreen = false
        guard let action = pendingPresentation else { return }
        panelHeld = true
        pendingPresentation = nil
        action()
        panelHeld = false
    }

    // MARK: Routing

    /// Opens a place asked for from outside the app: Siri, Shortcuts, a
    /// control, a notification.
    func route(to route: NewRoute) {
        showingSettings = false
        showingDays = false
        detail = nil
        if singlePage {
            selection = .today
            switch route {
            case .today:
                panelPath = NavigationPath()
                panelDetent = .peek
            case .search, .destination:
                panelPath = NavigationPath([route])
                panelDetent = .full
            }
            return
        }
        switch route {
        case .today:
            selection = .today
        case .search:
            selection = .search
            searchPath = NavigationPath()
        case .destination(let place):
            selection = place.tab
            searchPath = place.tab == .search ? NavigationPath([place]) : NavigationPath()
        }
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
