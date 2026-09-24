import SwiftUI

/// Oggi: the day's lessons, exams and deadlines under the shared
/// ``TodayBar``. In the single-page layout the same page hides the tab bar
/// and carries the ``SinglePagePanel``.
struct TodayTab: View {
    /// Drops the single-page panel back to its peek height, where it is out of the way of the day.
    private func minimizePanel() {
        guard shell.singlePage, shell.panelDetent != .peek else { return }
        withAnimation(.snappy) { shell.panelDetent = .peek }
    }

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// Whether the app is on screen, in the foreground or in the background.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        NavigationStack {
            ScrollView {
                DayTransition(day: shell.day) { day in
                    TodayLanding(day: day, style: style)
                }
                .padding(.bottom, shell.singlePage ? 120 : 40)
            }
            // The last step of onboarding promises this gesture, and every
            // other page that shows fetched data has it.
            .refreshable {
                async let day: Void = agenda.load(around: shell.day, force: true)
                async let career: Void = career.load(force: true)
                _ = await (day, career)
            }
            // Coming back to a page headed "Oggi" that is showing yesterday is
            // the tab lying about its own name: the day is set once at launch
            // and nothing moved it when midnight passed.
            //
            // Only a day already gone is taken back. Stepping *forward* to
            // next Tuesday is something the student did on purpose and may
            // well be mid-thought about when a notification pulls them away;
            // snapping that back on return would be the app overruling them.
            .onChange(of: scenePhase) { _, phase in
                let calendar = PoliMiDate.romeCalendar
                guard phase == .active,
                      shell.day < calendar.startOfDay(for: .now) else { return }
                shell.day = .now
            }
            // Using the page behind the panel tucks the panel away, as in Maps.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { minimizePanel() }
            }
            .simultaneousGesture(TapGesture().onEnded(minimizePanel))
            .dataStatusLine()
            .background(LookBackground(style: style).ignoresSafeArea())
            .todayBar()
            .toolbarVisibility(shell.singlePage ? .hidden : .automatic, for: .tabBar)
            .sheet(isPresented: Binding(get: { shell.showsPanel }, set: { _ in }),
                   onDismiss: shell.panelDidDismiss) {
                SinglePagePanel()
            }
        }
    }
}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}
