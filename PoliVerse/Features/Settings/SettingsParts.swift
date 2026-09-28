import SwiftUI
import UserNotifications

// The pieces Impostazioni is built from, shared by the phone's single list and
// the sidebar of the iPad and the Mac, so the three read as one screen arranged
// three ways: the same groups, in the same order, each page wearing the same
// tile wherever it appears.

// MARK: - Pages

extension ShellState.SettingsPage {
    /// The page's name, in the sidebar and on its row.
    var title: LocalizedStringKey {
        switch self {
        case .profile: "Profilo"
        case .general: "Generale"
        case .reminders: "Promemoria"
        case .data: "Dati e archiviazione"
        case .weBeep: "WeBeep e diagnostica"
        case .menuBar: "Barra dei menu"
        case .about: "Informazioni"
        }
    }

    /// The SF Symbol on the page's tile.
    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .general: "slider.horizontal.3"
        case .reminders: "bell"
        case .data: "externaldrive"
        case .weBeep: "books.vertical"
        case .menuBar: "menubar.rectangle"
        case .about: "info.circle"
        }
    }

    /// Where the page's tile sits on the look's ramp. Fixed per page, so the
    /// Dati tile is the same colour at the top of the phone's list, in the
    /// iPad's sidebar and in the Mac's.
    var tone: SettingsTone {
        switch self {
        case .profile, .general: .step(0)
        case .menuBar: .step(0.2)
        case .reminders: .step(0.4)
        case .data: .step(0.6)
        case .weBeep: .step(0.8)
        case .about: .neutral
        }
    }
}

// MARK: - Icons

/// Where a settings tile takes its colour from the look's ramp.
enum SettingsTone {
    /// A step on the ramp, from 0 (deepest) to 1 (palest).
    case step(Double)
    /// The ramp with the colour taken out: rows about the app rather than
    /// about the student.
    case neutral

    /// The colour for this tone on a ramp.
    ///
    /// - Parameter ramp: The look's ramp.
    /// - Returns: The tile's colour.
    func colour(in ramp: FlavorRamp) -> Flavor.RGB {
        switch self {
        case .step(let position): ramp.colour(at: position)
        case .neutral: ramp.neutral
        }
    }
}

/// A settings row's icon: a small solid tile in the look's colours, as the
/// rows of Promemoria wear theirs, rather than a bare symbol in the tint.
struct SettingsIcon: View {
    /// The tile's SF Symbol.
    let symbol: String
    /// Where the tile's colour sits on the look's ramp.
    let tone: SettingsTone
    /// The tile's side, in points.
    var side: CGFloat = 30

    /// The look in use.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        GlassTile(symbol: symbol, colour: tone.colour(in: FlavorRamp(style: style, scheme: scheme)), side: side)
            .accessibilityHidden(true)
    }
}

/// A page as a row: its tile and its name.
struct SettingsPageLabel: View {
    /// The page the row opens.
    let page: ShellState.SettingsPage
    /// The tile's side, in points.
    var side: CGFloat = 30

    /// The view's content.
    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            SettingsIcon(symbol: page.symbol, tone: page.tone, side: side)
        }
    }
}

// MARK: - Profile

/// Who is signed in, as the first row of Impostazioni: the avatar, the name,
/// and the course and matricola under it.
struct SettingsProfileCard: View {
    /// The avatar's side, in points.
    var avatarSide: CGFloat = 56

    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes

    /// The view's content.
    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatar(student: session.student, size: avatarSide)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.student?.fullName ?? String(localized: "Ospite"))
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Vedi e modifica il profilo"))
    }

    /// The degree course and the matricola, whichever are known; the way in
    /// when neither is.
    private var subtitle: String {
        let parts = [programmes.programme?.degreeLabel, session.student?.matricola]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? String(localized: "Vedi e modifica il profilo") : parts.joined(separator: " · ")
    }
}

// MARK: - Status

/// The two things in Impostazioni that change by themselves — whether the data
/// is fresh, and whether WeBeep is still signed in — as tiles side by side at
/// the top, each the way in to its page.
///
/// They replace the two rows that used to carry the same news as a subtitle:
/// a student who opens Impostazioni because something looks stale should see
/// the answer before reading a single row.
struct SettingsStatusTiles: View {
    /// The page selected in a sidebar, which the matching tile rings. `nil` on
    /// a phone, where a tile pushes its page instead.
    var selection: ShellState.SettingsPage?
    /// Whether each tile shows it leads somewhere: on a phone it pushes, in a
    /// sidebar it selects.
    var showsChevron = true
    /// Opens a tile's page.
    let open: (ShellState.SettingsPage) -> Void

    /// The shared ``DataStatus``, from the environment.
    @Environment(DataStatus.self) private var status
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep

    /// The view's content.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tile(.data, title: "Dati", line: Text(status.summary),
                 dot: status.badge == nil ? .green : .orange)
            tile(.weBeep, title: "WeBeep",
                 line: Text(weBeep.isAuthenticated ? "Collegato" : "Non collegato"),
                 dot: weBeep.isAuthenticated ? .green : .secondary)
        }
    }

    /// One tile: the page's icon, a short name, and its state under it.
    ///
    /// - Parameters:
    ///   - page: The page the tile opens.
    ///   - title: The tile's short name.
    ///   - line: The state, in one line or two.
    ///   - dot: The colour of the mark beside the state.
    /// - Returns: The tile.
    private func tile(_ page: ShellState.SettingsPage, title: LocalizedStringKey, line: Text,
                      dot: Color) -> some View {
        let isSelected = selection == page
        return Button { open(page) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsIcon(symbol: page.symbol, tone: page.tone)
                    Spacer(minLength: 0)
                    if showsChevron {
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dot)
                            .frame(width: 7, height: 7)
                        line
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(.rect(cornerRadius: 22))
            .lookCard(cornerRadius: 22)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-status-\(page)")
    }
}

// MARK: - Studies

/// The degree course and approved plan, and the favourite campus: what the
/// journey asked, changed later.
struct SettingsStudiesSection: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``RoomsModel``, from the environment.
    @Environment(RoomsModel.self) private var rooms
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var freeRooms
    /// The campus Aule libere opens on.
    @AppStorage(FavouriteCampus.storageKey) private var favouriteCampus = ""
    /// Whether the plan picker is up.
    @State private var choosingPlan = false

    /// The view's content.
    var body: some View {
        Section {
            if !session.useMockData {
                Button { choosingPlan = true } label: {
                    LabeledContent {
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Corso di studi e piano")
                                Text(planSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            SettingsIcon(symbol: "graduationcap", tone: .step(0.1))
                        }
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-programme")
            }
            Picker(selection: Binding(get: { favouriteCampus }, set: { campus in
                favouriteCampus = campus
                if let main = rooms.mainCampus(inSite: campus) { freeRooms.campus = main }
            })) {
                if !rooms.sites.contains(favouriteCampus) {
                    Text("Nessuna").tag(favouriteCampus)
                }
                ForEach(rooms.sites, id: \.self) { Text($0).tag($0) }
            } label: {
                Label {
                    Text("Sede preferita")
                } icon: {
                    SettingsIcon(symbol: "building.2", tone: .step(0.3))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings-campus")
        } header: {
            Text("I tuoi studi")
        } footer: {
            if session.useMockData {
                Text("La sede è dove si aprono le aule libere.")
            } else {
                Text("Il piano approvato (PSPA) decide le schede dei corsi, il syllabus e l’orario personalizzato; la sede è dove si aprono le aule libere.")
            }
        }
        .lookRow()
        .task { await rooms.load() }
        .sheet(isPresented: $choosingPlan) { StudyProgrammeSheet() }
    }

    /// The degree and the plan in one line, or what is missing.
    private var planSummary: String {
        guard let programme = programmes.programme else { return String(localized: "Da scegliere") }
        return [programme.degreeLabel, programme.planLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Layout

#if os(iOS)
/// Tabs or one page, chosen by picture, and the keyboard in Cerca when there
/// are tabs. The Mac has one layout, the sidebar, and no keyboard to bring up.
struct SettingsLayoutSection: View {
    /// How the app is laid out: tabs, or one page with a panel.
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    /// Whether opening Cerca brings the keyboard up.
    @AppStorage(SearchTabKeyboard.storageKey) private var searchOpensKeyboard = true
    /// Wide enough to draw the choices as an iPad rather than a phone.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The view's content.
    var body: some View {
        Section {
            // Two pictures side by side rather than a menu: the difference is
            // where things are on screen, which a drawing says at once and a
            // word like "Pagina unica" does not. Picking one closes the sheet
            // and rearranges the app underneath (see ``RootView``).
            HStack(spacing: 12) {
                ForEach(AppLayout.allCases) { option in
                    LayoutChoice(option: option, isSelected: layout == option,
                                 landscape: sizeClass == .regular) {
                        layout = option
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-layout")

            if layout == .tabs {
                Toggle(isOn: $searchOpensKeyboard) {
                    Label {
                        Text("Apri la tastiera in Cerca")
                    } icon: {
                        SettingsIcon(symbol: "keyboard", tone: .neutral)
                    }
                }
            }
        } header: {
            Text("Disposizione")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(layout.detail)
                if layout == .tabs {
                    Text(searchOpensKeyboard
                         ? "Toccando Cerca il campo si attiva subito."
                         : "Toccando Cerca vedi prima le ricerche recenti e i luoghi; la tastiera si apre quando tocchi il campo.")
                }
            }
        }
        .lookRow()
    }
}

/// One layout as a card: a drawing of the screen, its name, and a mark when
/// it is the one in use.
private struct LayoutChoice: View {
    /// The layout this card picks.
    let option: AppLayout
    /// Whether it is the layout in use.
    let isSelected: Bool
    /// Drawn as a tablet on its side rather than a phone.
    let landscape: Bool
    /// Picks the layout.
    let choose: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: choose) {
            VStack(spacing: 10) {
                LayoutThumbnail(layout: option, landscape: landscape)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .contentShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                  lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.title))
        .accessibilityHint(Text(option.detail))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings-layout-\(option.rawValue)")
    }
}

/// A small drawing of a layout: the tab bar with a page of cards, or one page
/// with the panel risen from the bottom.
private struct LayoutThumbnail: View {
    /// The layout drawn.
    let layout: AppLayout
    /// A tablet on its side rather than a phone.
    let landscape: Bool

    /// The drawing's size.
    private var size: CGSize {
        landscape ? CGSize(width: 116, height: 82) : CGSize(width: 70, height: 124)
    }

    /// The colour of the device's edge and of the placeholder lines.
    private let edge = Color.primary.opacity(0.22)

    /// The view's content.
    var body: some View {
        let screen = RoundedRectangle(cornerRadius: landscape ? 12 : 16, style: .continuous)
        content
            .frame(width: size.width, height: size.height)
            .background(Color.primary.opacity(0.06))
            .clipShape(screen)
            .overlay { screen.strokeBorder(edge, lineWidth: 2) }
            .accessibilityHidden(true)
    }

    /// What is on the drawn screen.
    @ViewBuilder private var content: some View {
        switch layout {
        case .tabs:
            VStack(spacing: 5) {
                // An iPad keeps its tab bar at the top; a phone at the bottom.
                if landscape { tabBar }
                title
                card
                card
                Spacer(minLength: 0)
                if !landscape { tabBar }
            }
            .padding(EdgeInsets(top: landscape ? 7 : 10, leading: 7, bottom: 7, trailing: 7))
        case .singlePage:
            VStack(spacing: 0) {
                VStack(spacing: 5) {
                    title
                    card.frame(height: landscape ? 22 : 34)
                }
                .padding(EdgeInsets(top: landscape ? 7 : 10, leading: 7, bottom: 0, trailing: 7))
                Spacer(minLength: 0)
                UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
                    .fill(.background)
                    .frame(height: size.height * 0.36)
                    .shadow(color: .black.opacity(0.10), radius: 4, y: -1)
                    .overlay(alignment: .top) {
                        Capsule().fill(edge).frame(width: 18, height: 3).padding(.top, 5)
                    }
            }
        }
    }

    /// The page's title, as a short line.
    private var title: some View {
        Capsule()
            .fill(edge)
            .frame(width: size.width * 0.4, height: 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A card on the page.
    private var card: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.background)
            .frame(height: landscape ? 16 : 22)
    }

    /// The tab bar, with the first tab lit.
    private var tabBar: some View {
        Capsule()
            .fill(.background)
            .frame(width: landscape ? 60 : nil, height: 14)
            .overlay {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(edge))
                            .frame(width: 5, height: 5)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
    }
}
#endif

// MARK: - Reminders

/// Promemoria as a row, with what it will actually do under the name — so a
/// student can tell from here whether reminders are on at all.
struct SettingsRemindersLabel: View {
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications

    /// The view's content.
    var body: some View {
        let page = ShellState.SettingsPage.reminders
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            SettingsIcon(symbol: page.symbol, tone: page.tone)
        }
        .task { await notifications.refreshAuthorization() }
    }

    /// The kinds switched on, or why none will arrive.
    private var summary: String {
        switch notifications.authorization {
        case .denied: return String(localized: "Disattivati nelle impostazioni di sistema")
        case .notDetermined: return String(localized: "Non ancora attivati")
        default: break
        }
        let preferences = notifications.preferences
        let kinds = [
            preferences.lectures ? String(localized: "lezioni") : nil,
            preferences.deadlines ? String(localized: "scadenze") : nil,
            preferences.exams ? String(localized: "esami") : nil,
            preferences.enrolments ? String(localized: "iscrizioni") : nil,
        ].compactMap { $0 }
        guard !kinds.isEmpty else { return String(localized: "Nessun promemoria attivo") }
        let list = kinds.formatted(.list(type: .and))
        return list.prefix(1).uppercased() + list.dropFirst()
    }
}

// MARK: - About

/// The version, the notes for it, and the first run again.
struct SettingsAboutSection: View {
    /// The shared ``WhatsNewState``, from the environment.
    @Environment(WhatsNewState.self) private var whatsNew
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Closes Impostazioni: the Settings window on the Mac.
    @Environment(\.dismiss) private var dismiss
    /// The environment's `shell`, whose flag presents the sheet on iOS.
    @Environment(\.shell) private var shell
    /// Opened from the row below, rather than by the shell: a sheet raised
    /// over Impostazioni from outside it never comes up.
    @State private var readingNotes: [ReleaseNote] = []

    /// The view's content.
    var body: some View {
        Section {
            // The update's notes are shown once, over an app someone opened to
            // do something else: this is where they are read properly,
            // afterwards. The version sits beside them, so the row says which
            // version the notes are for.
            if whatsNew.hasCurrentNote {
                Button { readingNotes = whatsNew.currentNotes } label: {
                    LabeledContent {
                        Text(Bundle.main.appVersion)
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text("Novità di questa versione")
                        } icon: {
                            SettingsIcon(symbol: "sparkles", tone: .step(0.5))
                        }
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-whats-new")
            } else {
                LabeledContent {
                    Text(Bundle.main.appVersion)
                        .monospacedDigit()
                } label: {
                    Label {
                        Text("Versione")
                    } icon: {
                        SettingsIcon(symbol: "info.circle", tone: .neutral)
                    }
                }
            }
            // The first run, again: the tour and the settings it asks for
            // once. Impostazioni closes first, because the flow takes the
            // place of the app underneath it.
            Button {
                // Through the shell on iOS: from the page beside an iPad's
                // sidebar, `dismiss` would not reach the sheet.
                #if os(iOS)
                shell.showingSettings = false
                #else
                dismiss()
                #endif
                onboarding.replay()
            } label: {
                Label {
                    Text("Rivedi il benvenuto")
                } icon: {
                    SettingsIcon(symbol: "hand.wave", tone: .neutral)
                }
            }
            .tint(.primary)
            .accessibilityIdentifier("settings-replay-onboarding")
        } header: {
            Text("Informazioni")
        }
        .lookRow()
        .sheet(isPresented: Binding(get: { !readingNotes.isEmpty },
                                    set: { if !$0 { readingNotes = [] } })) {
            WhatsNewView(notes: readingNotes, saysWhereToFindItAgain: false) { readingNotes = [] }
        }
    }
}

/// Informazioni as a page of its own, for the sidebar.
struct SettingsAboutPane: View {
    /// The view's content.
    var body: some View {
        List {
            SettingsAboutSection()
            Section {
            } footer: {
                SettingsDisclaimer()
            }
        }
        .lookList()
        .navigationTitle("Informazioni")
    }
}

// MARK: - Sign out

/// Esci, with the confirmation that says what goes with it.
struct SettingsSignOutButton: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// Whether the sign-out confirmation is presented.
    @State private var confirming = false

    /// The view's content.
    var body: some View {
        Button(role: .destructive) { confirming = true } label: {
            Text("Esci")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("settings-sign-out")
        .confirmationDialog("Uscire dall’account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Esci", role: .destructive) {
                Task { await session.login.signOut() }
            }
        } message: {
            Text("Vengono rimossi i token dal portachiavi e i dati salvati sul dispositivo.")
        }
    }
}

/// The line that closes Impostazioni everywhere.
struct SettingsDisclaimer: View {
    /// The view's content.
    var body: some View {
        Text("PoliVerse non è affiliata al Politecnico di Milano.")
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Generale

/// The settings a phone shows inline on its first page, as the first pane of
/// the sidebar layout: the studies, and the layout (iPad) or how the app
/// starts (Mac).
struct SettingsGeneralPane: View {
    /// Opens another page of Impostazioni, for the status tiles on the Mac.
    let open: (ShellState.SettingsPage) -> Void

    /// The view's content.
    var body: some View {
        List {
            // The iPad's sidebar has room for the status tiles above its rows;
            // the Mac's is a column of plain rows, so its tiles sit here.
            #if os(macOS)
            SettingsStatusTiles(showsChevron: false, open: open)
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            #endif
            SettingsStudiesSection()
            #if os(iOS)
            SettingsLayoutSection()
            #else
            LoginItemSection()
            #endif
        }
        .lookList()
        .navigationTitle("Generale")
    }
}

/// Any page of Impostazioni, by name.
struct SettingsPageView: View {
    /// The page shown.
    let page: ShellState.SettingsPage
    /// Opens another page, for panes that lead to one.
    var open: (ShellState.SettingsPage) -> Void = { _ in }

    /// The view's content.
    var body: some View {
        switch page {
        case .profile: ProfileView()
        case .general: SettingsGeneralPane(open: open)
        case .reminders: NotificationSettingsView()
        case .data: DataStorageView()
        case .weBeep: ConnectionsView()
        case .menuBar:
            #if os(macOS)
            MenuBarSettingsPane()
            #else
            SettingsGeneralPane(open: open)
            #endif
        case .about: SettingsAboutPane()
        }
    }
}
