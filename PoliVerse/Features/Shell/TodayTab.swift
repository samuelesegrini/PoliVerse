import SwiftUI

/// Oggi: the day's lessons, exams and deadlines under the shared
/// ``TodayBar``. In the single-page layout the same page hides the tab bar
/// and carries the ``SinglePagePanel``.
struct TodayTab: View {
    private func minimizePanel() {
        guard shell.singlePage, shell.panelDetent != .peek else { return }
        withAnimation(.snappy) { shell.panelDetent = .peek }
    }

    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        NavigationStack {
            ScrollView {
                DayTransition(day: shell.day) { day in
                    TodayLanding(day: day, style: style)
                }
                .padding(.bottom, shell.singlePage ? 120 : 40)
            }
            // Using the page behind the panel tucks the panel away, as in Maps.
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { minimizePanel() }
            }
            .simultaneousGesture(TapGesture().onEnded(minimizePanel))
            .dataStatusLine()
            .background(TodayBackgroundView(style: style).ignoresSafeArea())
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
