import SwiftUI

/// The Oggi tab of the tab layout: the day's lessons, exams and deadlines,
/// under the shared ``TodayBar``.
struct TodayTab: View {
    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, style: style)
                    .padding(.bottom, 40)
            }
            .todayBar()
        }
    }
}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}
