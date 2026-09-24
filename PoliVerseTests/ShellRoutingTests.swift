import SwiftUI
import Testing
@testable import PoliVerse

/// A way in from outside opens the same place in either layout: a tab, or the
/// single page's panel pushed to it.
@MainActor
@Suite("New interface routing")
struct ShellRoutingTests {
    @Test("Tabs: a tab place selects its tab, any other place opens its tab pushed to it")
    func tabs() {
        let shell = ShellState()
        shell.showingSettings = true
        shell.route(to: .destination(.career))
        #expect(shell.selection == .career)
        #expect(shell.careerPath.isEmpty)
        #expect(!shell.showingSettings)

        // The calendar lives in Oggi, the study plan in Carriera, the rest in Cerca.
        shell.route(to: .destination(.calendar))
        #expect(shell.selection == .today)
        #expect(shell.todayPath == NavigationPath([NewDestination.calendar]))

        shell.route(to: .destination(.studyPlan))
        #expect(shell.selection == .career)
        #expect(shell.careerPath == NavigationPath([NewDestination.studyPlan]))

        shell.route(to: .destination(.freeRooms))
        #expect(shell.selection == .search)
        #expect(shell.searchPath == NavigationPath([NewDestination.freeRooms]))

        shell.route(to: .search)
        #expect(shell.selection == .search)
        #expect(shell.searchPath.isEmpty)

        shell.route(to: .today)
        #expect(shell.selection == .today)
    }

    @Test("Single page: the panel rises to full height, pushed to the place")
    func singlePage() {
        let shell = ShellState()
        shell.singlePage = true
        shell.route(to: .destination(.courses))
        #expect(shell.selection == .today)
        #expect(shell.panelPath == NavigationPath([NewRoute.destination(.courses)]))
        #expect(shell.panelDetent == .full)

        shell.route(to: .today)
        #expect(shell.panelPath.isEmpty)
        #expect(shell.panelDetent == .peek)
    }

    @Test("The profile opens as the first page of Impostazioni")
    func profile() {
        let shell = ShellState()
        shell.openProfile()
        #expect(shell.showingSettings)
        #expect(shell.settingsPath == [.profile])
    }

    @Test("A presentation waits for the panel only while the panel is on screen")
    func deferral() {
        let shell = ShellState()
        shell.singlePage = true
        var ran = false
        // Not on screen yet, as during the layout animation: nothing would
        // ever call back, so it runs straight away.
        shell.present { ran = true }
        #expect(ran)

        ran = false
        shell.panelIsOnScreen = true
        shell.present { ran = true }
        #expect(!ran)
        shell.panelIsOnScreen = false
        shell.panelDidDismiss()
        #expect(ran)
    }
}
