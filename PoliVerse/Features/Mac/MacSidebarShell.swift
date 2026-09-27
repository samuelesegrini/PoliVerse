#if os(macOS)
import SwiftUI

/// The Mac's navigation: a sidebar listing Oggi, Corsi, Carriera and Cerca, then the
/// places that live inside Cerca on iPhone, each opening as its own page.
///
/// Drives the same ``ShellSelection`` the iPhone's tab view does, so routes from Siri,
/// Controls, notifications and the Vai menu land the same way.
struct MacSidebarShell: View {
    /// The selected tab or place, shared with ``RootView``.
    @Binding var selection: ShellSelection
    /// What changed since the feed was last opened, badged on Carriera.
    let unread: Int

    @Environment(Session.self) private var session
    /// The shell, whose detail opens in an inspector beside the page.
    @Environment(\.shell) private var shell
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    @Environment(CareerModel.self) private var career
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<ShellSelection?>(get: { selection }, set: { if let new = $0 { selection = new } })) {
                Section {
                    row("Oggi", "calendar.day.timeline.left", .tab(.today))
                    row(NewDestination.courses.title, NewDestination.courses.systemImage, .tab(.courses))
                    row(NewDestination.career.title, NewDestination.career.systemImage, .tab(.career))
                        .badge(unread)
                    row("Cerca", "magnifyingglass", .tab(.search))
                }
                Section("Campus e studio") {
                    ForEach(NewDestination.inSearch + [.calendar, .studyPlan]) { place in
                        row(place.title, place.systemImage, .place(place))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .safeAreaInset(edge: .bottom) { profile }
        } detail: {
            @Bindable var shell = shell
            detail
                // A lecture, sitting or deadline opened from any page, beside it.
                .detailPresentation(item: $shell.detail) { $0.view }
        }
        #if DEBUG
        .onAppear {
            MacSnapshots.openSettings = openSettings
            MacSnapshots.showExam = { [shell, career] in
                if let exam = career.upcoming.first ?? career.sessions.first { shell.detail = .exam(exam) }
            }
        }
        #endif
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ value: ShellSelection) -> some View {
        Label(title, systemImage: symbol)
            .tag(value)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .tab(.today): TodayTab().accessibilityIdentifier("tab-today")
        case .tab(.courses): CoursesTab().accessibilityIdentifier("tab-courses")
        case .tab(.career): CareerTab().accessibilityIdentifier("tab-career")
        case .tab(.search): SearchTab().accessibilityIdentifier("tab-search")
        case .place(let place): SidebarPlace(place: place)
        }
    }

    /// Who is signed in, at the foot of the sidebar; a click opens Settings.
    @ViewBuilder
    private var profile: some View {
        if let student = session.student {
            SettingsLink {
            HStack(spacing: 10) {
                ProfileAvatar(student: student, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(student.fullName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(student.matricola).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Impostazioni")
        }
    }
}
#endif
