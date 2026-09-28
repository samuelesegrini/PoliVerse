#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

/// The Mac app's delegate: keeps the app running with no window open, and applies the
/// Dock setting at launch.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DockPolicy.apply(hidden: UserDefaults.standard.bool(forKey: DockPolicy.storageKey))
        #if DEBUG
        // `-MacSnapshots` writes every window, and the menu bar panel, to PNGs in
        // ~/Downloads/PoliVerse Snapshots, for checking layouts without a screen.
        if CommandLine.arguments.contains("-MacSnapshots") {
            Task { @MainActor in await MacSnapshots.run() }
        }
        #endif
    }

    /// The menu bar item keeps working after the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#if DEBUG
/// Renders the app's windows to PNG files, for checking layouts without a screen.
@MainActor
enum MacSnapshots {
    /// Builds the menu bar panel with the app's models, set by the app's scene.
    static var panel: (() -> AnyView)?
    /// Opens Settings, handed over by the main window.
    static var openSettings: OpenSettingsAction?
    /// Opens a sitting's detail, handed over by the main window.
    static var showExam: (() -> Void)?

    /// Renders the windows, opens the menu bar panel, and renders them again.
    static func run() async {
        try? await Task.sleep(for: .seconds(6))
        // Sheets over the window (Novità, onboarding) are closed, so the page shows.
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        try? await Task.sleep(for: .seconds(1))
        write(prefix: "window")
        // Each section in turn, routed the way the Vai menu does.
        for (name, destination) in [("courses", AppDestination.weBeep), ("career", .career),
                                    ("search", .search), ("freerooms", .freeRooms), ("today", .home)] {
            destination.send()
            try? await Task.sleep(for: .seconds(2.5))
            write(prefix: name, onlyFirst: true)
            if name == "career" {
                showExam?()
                try? await Task.sleep(for: .seconds(2.5))
                write(prefix: "career-inspector", onlyFirst: true)
                writeGlass(named: "inspector", pick: { $0.max { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX } })
            }
        }
        // Settings, opened the way ⌘, opens it.
        MacSnapshots.openSettings?()
        try? await Task.sleep(for: .seconds(2.5))
        for window in NSApp.windows where window.title != "Oggi" && window.frame.width > 400
            && window.frame.width < 1000 && window.isVisible {
            if let view = window.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("settings.png"))
            }
        }
        // Glass is not drawn by a cached display, so the sidebar's content is rendered on
        // its own.
        if let main = NSApp.windows.first, let frame = main.contentView?.superview,
           let glass = frame.allSubviews(of: NSGlassEffectView.self).max(by: { $0.bounds.height < $1.bounds.height }),
           let content = glass.contentView ?? glass.subviews.last,
           let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("sidebar.png"))
        }
        // Then the menu bar panel. The status item's own window is out of reach, so the
        // same view is hosted in an offscreen window of the panel's size.
        if let panel {
            let host = NSHostingView(rootView: panel())
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -3000, y: 0), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderBack(nil)
            try? await Task.sleep(for: .seconds(3))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            window.setContentSize(host.fittingSize)
            try? await Task.sleep(for: .seconds(1))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("panel.png"))
            }
            window.orderOut(nil)
        }
        dumpViews()
        NSLog("MacSnapshots written to %@", folder.path)
    }

    /// ~/Downloads/PoliVerse Snapshots, which the sandbox lets the app write to.
    private static var folder: URL {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PoliVerse Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes each window's view classes, three levels of NSView, for finding what a
    /// capture leaves blank.
    private static func dumpViews() {
        var lines: [String] = []
        func walk(_ view: NSView, _ depth: Int) {
            guard depth < 16 else { return }
            lines.append(String(repeating: "  ", count: depth) + "\(type(of: view)) \(Int(view.frame.minX)),\(Int(view.frame.minY)) \(Int(view.frame.width))x\(Int(view.frame.height))")
            view.subviews.forEach { walk($0, depth + 1) }
        }
        for window in NSApp.windows {
            lines.append("== \(window.title) \(type(of: window))")
            if let view = window.contentView?.superview { walk(view, 0) }
        }
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("views.txt"), atomically: true, encoding: .utf8)
    }

    /// Writes the content of one tall glass pane (sidebar or inspector), which a cached
    /// display of the window leaves blank.
    private static func writeGlass(named name: String, pick: ([NSGlassEffectView]) -> NSGlassEffectView?) {
        guard let frame = NSApp.windows.first(where: { $0.title != "" && $0.frame.width > 800 })?.contentView?.superview
        else { return }
        let panes = frame.allSubviews(of: NSGlassEffectView.self).filter { $0.bounds.height > 400 }
        guard let glass = pick(panes), let content = glass.contentView ?? glass.subviews.last,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// Writes one PNG per window.
    private static func write(prefix: String, onlyFirst: Bool = false) {
        for (index, window) in NSApp.windows.enumerated() where !onlyFirst || index == 0 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  view.bounds.width > 40, view.bounds.height > 40,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = folder.appendingPathComponent(
                "\(prefix)-\(index)-\(Int(view.bounds.width))x\(Int(view.bounds.height)).png")
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: url)
            } catch {
                NSLog("MacSnapshots failed: %@", error.localizedDescription)
            }
        }
    }
}

private extension NSView {
    /// Every view of a type in this view's tree.
    func allSubviews<T: NSView>(of type: T.Type) -> [T] {
        (self as? T).map { [$0] } ?? [] + subviews.flatMap { $0.allSubviews(of: type) }
    }

    /// The first view of a type in this view's tree, this one included.
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in subviews {
            if let match = child.firstSubview(of: type) { return match }
        }
        return nil
    }
}
#endif

/// Whether PoliVerse shows in the Dock, or lives only in the menu bar.
enum DockPolicy {
    /// The user-defaults key for "solo nella barra dei menu".
    static let storageKey = "mac.dockHidden"

    /// Shows or hides the Dock icon and the app's menus.
    ///
    /// - Parameter hidden: `true` to live only in the menu bar.
    static func apply(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if !hidden { NSApp.activate() }
    }
}

/// Opening PoliVerse when the student logs in to the Mac, through the login items.
enum LoginItem {
    /// Whether PoliVerse is a login item right now. Read each time, because the
    /// student can turn it off in System Settings.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Adds or removes PoliVerse from the login items.
    ///
    /// - Parameter enabled: Whether it should open at login.
    /// - Throws: What ServiceManagement reports when it refuses.
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Menus

/// The app's own menus: a Vai menu with a shortcut for every place, and Aggiorna.
struct PoliVerseCommands: Commands {
    /// Revalidates every screen's data.
    let freshness: FreshnessCoordinator

    var body: some Commands {
        CommandMenu("Vai") {
            Button("Oggi") { AppDestination.home.send() }
                .keyboardShortcut("1")
            Button("Corsi") { AppDestination.weBeep.send() }
                .keyboardShortcut("2")
            Button("Carriera") { AppDestination.career.send() }
                .keyboardShortcut("3")
            Button("Cerca") { AppDestination.search.send() }
                .keyboardShortcut("4")
            Divider()
            Button("Calendario") { AppDestination.calendar.send() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Aule libere") { AppDestination.freeRooms.send() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Mappa del campus") { AppDestination.map.send() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Piano di studi") { AppDestination.plan.send() }
        }
        CommandGroup(after: .toolbar) {
            Button("Aggiorna") { Task { await freshness.revalidate(force: true) } }
                .keyboardShortcut("r")
        }
    }
}

// MARK: - Settings

/// The Mac's Settings window: the same sidebar as the iPad's Impostazioni, with the
/// pages the Mac has — Dati and WeBeep as rows, and the menu bar item's own pane.
struct MacSettingsView: View {
    var body: some View {
        SettingsSplitView()
            .frame(width: 760, height: 560)
    }
}

/// Settings › Generale › Avvio: whether the app opens when the Mac starts. In
/// Generale rather than Barra dei menu, because it holds whether or not the menu
/// bar item is shown.
struct LoginItemSection: View {
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Section {
            Toggle(isOn: $opensAtLogin) {
                Text("Apri all'accesso al Mac")
                Text("Anche in Impostazioni di Sistema › Generali › Elementi di login.")
            }
            .onChange(of: opensAtLogin) { _, enabled in
                do {
                    try LoginItem.set(enabled)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                    opensAtLogin = LoginItem.isEnabled
                }
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Avvio")
        } footer: {
            Text("Cosa mostra la barra dei menu, e se l'app resta fuori dal Dock, si sceglie in Barra dei menu.")
        }
        .lookRow()
        .onAppear { opensAtLogin = LoginItem.isEnabled }
    }
}

/// Settings › Barra dei menu: whether the item shows, what it says, what the panel
/// holds, and whether the app keeps its Dock icon.
struct MenuBarSettingsPane: View {
    @Environment(MenuBarItemState.self) private var menuBarItem
    @AppStorage(MenuBarSettings.labelKey) private var label: MenuBarSettings.Label = .roomAndMinutes
    @AppStorage(MenuBarSettings.sectionsKey) private var hiddenSections = ""
    @AppStorage(DockPolicy.storageKey) private var dockHidden = false

    var body: some View {
        @Bindable var menuBarItem = menuBarItem
        let shown = menuBarItem.isInserted
        Form {
            Section {
                Toggle(isOn: $menuBarItem.isInserted) {
                    Text("Mostra PoliVerse nella barra dei menu")
                    Text("La lezione in corso e le prossime scadenze, a un clic.")
                }
                Picker("Nella barra", selection: $label) {
                    ForEach(MenuBarSettings.Label.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!shown)
            }
            Section("Nel pannello") {
                ForEach(MenuBarSettings.Section.allCases) { section in
                    Toggle(section.title, isOn: binding(for: section))
                }
            }
            .disabled(!shown)
            Section {
                Toggle(isOn: $dockHidden) {
                    Text("Solo nella barra dei menu")
                    Text("Niente icona nel Dock; la finestra si apre dal pannello.")
                }
                .disabled(!shown)
                .onChange(of: dockHidden) { _, hidden in DockPolicy.apply(hidden: hidden) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Barra dei menu")
        // Hiding the item while the Dock icon is hidden would leave no way back in.
        .onChange(of: menuBarItem.isInserted) { _, shown in
            if !shown && dockHidden {
                dockHidden = false
            }
        }
    }

    /// Whether a panel section shows, as a binding over the stored list of hidden ones.
    private func binding(for section: MenuBarSettings.Section) -> Binding<Bool> {
        Binding {
            !MenuBarSettings.hidden(from: hiddenSections).contains(section)
        } set: { visible in
            var hidden = MenuBarSettings.hidden(from: hiddenSections)
            if visible { hidden.remove(section) } else { hidden.insert(section) }
            hiddenSections = MenuBarSettings.Section.allCases
                .filter(hidden.contains).map(\.rawValue).joined(separator: ",")
        }
    }
}
#endif
