import SwiftUI

/// Impostazioni: one list on a phone, a sidebar beside the page on an iPad.
///
/// Both hold the same groups in the same order — the profile and the status
/// of the data and of WeBeep, then Generale, Promemoria and Informazioni, then
/// Esci — built from the pieces in `SettingsParts.swift`. The Mac shows the
/// sidebar layout in its Settings window (``MacSettingsView``).
struct SettingsSheet: View {
    #if os(iOS)
    /// Regular on an iPad sheet, where there is room for a sidebar.
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// The view's content.
    var body: some View {
        #if os(iOS)
        Group {
            if sizeClass == .regular {
                SettingsSplitView()
            } else {
                SettingsPhoneList()
            }
        }
        // A page-sized sheet on an iPad, wide enough for the sidebar and the
        // page beside it; a phone's sheet is the same either way.
        .presentationSizing(.page)
        #else
        SettingsSplitView()
        #endif
    }
}

#if os(iOS)
/// Impostazioni on a phone: every group in one list, with Generale's settings
/// inline so the ones a student changes most are one tap away.
private struct SettingsPhoneList: View {
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// The view's content.
    var body: some View {
        NavigationStack(path: Binding(get: { shell.settingsPath }, set: { shell.settingsPath = $0 })) {
            List {
                Section {
                    NavigationLink(value: ShellState.SettingsPage.profile) {
                        SettingsProfileCard()
                    }
                    .accessibilityIdentifier("settings-profile")
                }
                .lookRow()

                Section {
                    SettingsStatusTiles { shell.settingsPath.append($0) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                SettingsStudiesSection()

                SettingsLayoutSection()

                Section {
                    NavigationLink(value: ShellState.SettingsPage.reminders) {
                        SettingsRemindersLabel()
                    }
                }
                .lookRow()

                SettingsAboutSection()

                Section {
                    SettingsSignOutButton()
                } footer: {
                    SettingsDisclaimer()
                }
                .lookRow()
            }
            .accessibilityIdentifier("settings-list")
            .lookList()
            .navigationTitle("Impostazioni")
            .navigationDestination(for: ShellState.SettingsPage.self) { page in
                SettingsPageView(page: page) { shell.settingsPath.append($0) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("settings-close")
                }
            }
        }
    }
}
#endif

/// Impostazioni with a sidebar: the iPad's sheet and the Mac's Settings window.
///
/// The sidebar lists the same groups the phone's list holds, and the page
/// beside it is the one selected. Generale opens first: it is the phone's
/// first page, less the rows that are now the sidebar's.
struct SettingsSplitView: View {
    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The page beside the sidebar.
    @State private var selection: ShellState.SettingsPage? = .general

    /// The pages the sidebar lists under the profile, in order.
    private var pages: [ShellState.SettingsPage] {
        #if os(macOS)
        // The Mac's sidebar is a column of plain rows, so Dati and WeBeep are
        // rows here and their status tiles sit at the top of Generale.
        [.general, .reminders, .data, .weBeep, .menuBar, .about]
        #else
        [.general, .reminders, .about]
        #endif
    }

    /// The view's content.
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                SettingsPageView(page: selection ?? .general) { selection = $0 }
            }
            // A fresh stack per page, so a page pushed inside one is not left
            // standing over the next.
            .id(selection)
        }
        // A way in from outside names a page (the profile, from the avatar in
        // the bar): select it, and clear the request so the next one fires.
        .onChange(of: shell.settingsPath, initial: true) { _, path in
            guard let page = path.last else { return }
            selection = page
            shell.settingsPath = []
        }
    }

    /// The profile, the status tiles on an iPad, the pages, and Esci at the foot.
    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: ShellState.SettingsPage.profile) {
                    #if os(macOS)
                    SettingsProfileCard(avatarSide: 32)
                    #else
                    SettingsProfileCard(avatarSide: 46)
                    #endif
                }
                .accessibilityIdentifier("settings-profile")
            }

            #if os(iOS)
            Section {
                SettingsStatusTiles(selection: selection, showsChevron: false) { selection = $0 }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            #endif

            Section {
                ForEach(pages, id: \.self) { page in
                    NavigationLink(value: page) {
                        #if os(macOS)
                        SettingsPageLabel(page: page, side: 20)
                        #else
                        SettingsPageLabel(page: page, side: 28)
                        #endif
                    }
                    .accessibilityIdentifier("settings-page-\(page)")
                }
            }
        }
        .accessibilityIdentifier("settings-list")
        .navigationTitle("Impostazioni")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                SettingsSignOutButton()
                    .buttonStyle(.bordered)
                    #if os(iOS)
                    .controlSize(.large)
                    #endif
                SettingsDisclaimer()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        #if os(iOS)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi", systemImage: "xmark") { shell.showingSettings = false }
                    .accessibilityIdentifier("settings-close")
            }
        }
        #else
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        // A Settings window's sidebar stays open: there is nothing to hide it for.
        .toolbar(removing: .sidebarToggle)
        #endif
    }
}

#Preview("Impostazioni") {
    SettingsSheet().previewEnvironment()
}
