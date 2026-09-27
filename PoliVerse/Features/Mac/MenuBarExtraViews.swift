#if os(macOS)
import Combine
import SwiftUI

/// What the student chose for PoliVerse in the menu bar, kept in user defaults.
enum MenuBarSettings {
    /// Whether the item is in the menu bar.
    static let shownKey = "mac.menuBar.shown"
    /// What the item shows beside its symbol.
    static let labelKey = "mac.menuBar.label"
    /// Whether the panel shows each section, by ``Section`` raw value.
    static let sectionsKey = "mac.menuBar.sections"

    /// What the menu bar item shows beside its symbol.
    enum Label: String, CaseIterable, Identifiable {
        /// Only the symbol.
        case icon
        /// The room and the minutes left, "B.3.2 · 23′".
        case roomAndMinutes
        /// The next lecture's name and time.
        case nextLecture

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .icon: "Solo icona"
            case .roomAndMinutes: "Aula e minuti"
            case .nextLecture: "Prossima lezione"
            }
        }
    }

    /// The panel's sections, in order.
    enum Section: String, CaseIterable, Identifiable {
        case now, laterToday, examAndCareer, webeep, shortcuts

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .now: "Lezione in corso"
            case .laterToday: "Poi oggi"
            case .examAndCareer: "Prossimo esame e carriera"
            case .webeep: "Nuovo su WeBeep"
            case .shortcuts: "Aule libere, Mappa e Cerca"
            }
        }
    }

    /// The sections the student hid, stored as a comma-separated list.
    static func hidden(from stored: String) -> Set<Section> {
        Set(stored.split(separator: ",").compactMap { Section(rawValue: String($0)) })
    }
}

/// Whether the menu bar item is inserted, read and written by hand.
///
/// Kept out of `@AppStorage` on the app: the status item writes its own state to user
/// defaults, and anything observing defaults at the scene level would rebuild the item
/// on each write, which writes again.
@Observable
final class MenuBarItemState {
    /// Whether the item is in the menu bar.
    var isInserted: Bool {
        didSet { UserDefaults.standard.set(isInserted, forKey: MenuBarSettings.shownKey) }
    }

    init() {
        isInserted = UserDefaults.standard.object(forKey: MenuBarSettings.shownKey) as? Bool ?? true
    }
}

/// A scene's content with the look in use: its colour on the controls, and the look in
/// the environment for the views that draw with it.
struct LookedScene<Content: View>: View {
    @AppStorage(TodayStyle.storageKey) private var todayStyle = TodayStyle()
    @ViewBuilder let content: Content

    var body: some View {
        content
            .lookControls()
            .environment(\.look, todayStyle.resolved)
    }
}

/// Opens the main window on a place, from a scene that has no window of its own.
struct OpenInMainWindow {
    /// Opens windows by id.
    let openWindow: OpenWindowAction

    /// Brings the main window forward, then routes it.
    ///
    /// - Parameter destination: Where to go, or `nil` to open the window as it is.
    func callAsFunction(_ destination: AppDestination? = nil) {
        openWindow(id: PoliVerseApp.mainWindowID)
        NSApp.activate()
        destination?.send()
    }
}

// MARK: - The label

/// The item in the menu bar: the Orbita symbol, and optionally the room and the
/// minutes left, or the next lecture.
struct MenuBarLabel: View {
    @Environment(AgendaModel.self) private var agenda
    @AppStorage(MenuBarSettings.labelKey) private var label: MenuBarSettings.Label = .roomAndMinutes
    /// Moved on every half minute. A `TimelineView` here sends the status item into an
    /// endless redraw, so a plain timer drives the label instead.
    @State private var now = Date.now

    var body: some View {
        let current = CurrentClass.forAccessory(from: agenda.events, now: now)
        Group {
            if let text = text(for: current, at: now) {
                Text("\(Image(systemName: "graduationcap")) \(text)")
            } else {
                Image(systemName: "graduationcap")
            }
        }
        .accessibilityLabel("PoliVerse")
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// The words beside the symbol, or `nil` for the symbol alone.
    private func text(for current: CurrentClass?, at now: Date) -> String? {
        guard let current else { return nil }
        switch label {
        case .icon:
            return nil
        case .roomAndMinutes:
            let target = current.isOngoing ? current.event.end : current.event.start
            let minutes = max(Int(target.timeIntervalSince(now) / 60), 0)
            let time = minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))" : "\(minutes)′"
            return [current.event.roomLabel, time].compactMap { $0 }.joined(separator: " · ")
        case .nextLecture:
            return "\(current.event.title) \(current.event.start.formatted(date: .omitted, time: .shortened))"
        }
    }
}

// MARK: - The panel

/// The panel under the menu bar item: the class now, the rest of today, the next exam
/// and the career, new WeBeep material, and shortcuts into the app.
///
/// Reads the same models as the main window and never fetches by itself: opening it
/// asks the freshness coordinator to revalidate, which respects each model's window.
struct MenuBarPanel: View {
    @Environment(Session.self) private var session
    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(FreeRoomsModel.self) private var freeRooms
    @Environment(FreshnessCoordinator.self) private var freshness
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(MenuBarSettings.sectionsKey) private var hiddenSections = ""

    private var calendar: Calendar { PoliMiDate.romeCalendar }
    private var open: OpenInMainWindow { OpenInMainWindow(openWindow: openWindow) }
    private var hidden: Set<MenuBarSettings.Section> { MenuBarSettings.hidden(from: hiddenSections) }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 10) {
                header(now: now)
                if session.student == nil && !session.useMockData {
                    signedOut
                } else {
                    content(now: now)
                }
            }
            .padding(12)
            .frame(width: 360)
        }
        .task { await freshness.revalidate() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let current = CurrentClass.forAccessory(from: agenda.events, now: now)
        if !hidden.contains(.now), let current {
            nowCard(current, now: now)
        }
        if !hidden.contains(.laterToday) {
            let later = agenda.events
                .filter { calendar.isDate($0.start, inSameDayAs: now) && $0.start > now && $0.id != current?.event.id }
                .sorted { $0.start < $1.start }
                .prefix(3)
            if !later.isEmpty {
                PanelSection("Poi oggi") {
                    ForEach(Array(later), id: \.id) { event in
                        Button { open(.calendar) } label: {
                            PanelRow(symbol: event.kind.icon, title: event.title,
                                     detail: [event.start.formatted(date: .omitted, time: .shortened), event.roomLabel]
                                        .compactMap { $0 }.joined(separator: " · "),
                                     trailing: event.start.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if !hidden.contains(.examAndCareer) {
            HStack(spacing: 8) {
                if let exam = career.upcoming.first {
                    Button { open(.career) } label: {
                        tile("Prossimo esame", exam.courseName,
                             exam.date.map { $0.formatted(.relative(presentation: .named)) } ?? "Data da definire")
                    }
                    .buttonStyle(.plain)
                }
                if let mean = career.weightedMean {
                    Button { open(.career) } label: {
                        tile("Carriera", mean.formatted(.number.precision(.fractionLength(1))),
                             "media · \(career.studyPlan.earnedCFU)/\(career.studyPlan.totalCFU) CFU")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !hidden.contains(.webeep) {
            let recent = feed.recent.prefix(3)
            if !recent.isEmpty {
                PanelSection("Nuovo su WeBeep", badge: feed.unreadCount) {
                    ForEach(Array(recent), id: \.id) { update in
                        Button { open(.weBeep) } label: {
                            PanelRow(symbol: update.kind.symbol, title: update.title,
                                     detail: update.courseName, trailing: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if !hidden.contains(.shortcuts) {
            HStack(spacing: 8) {
                shortcut(freeRooms.rooms.isEmpty ? "Aule libere" : "\(freeRooms.freeNow().count) aule libere",
                         "door.left.hand.open") { open(.freeRooms) }
                shortcut("Mappa", "map") { open(.map) }
                shortcut("Cerca", "magnifyingglass") { open(.search) }
            }
        }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // Only the first letter: Italian keeps the month in lower case.
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).prefix(1).uppercased()
                     + now.formatted(.dateTime.weekday(.wide).day().month(.wide)).dropFirst())
                    .font(.headline)
                Text(freshnessLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Impostazioni", systemImage: "gearshape") {
                openSettings()
                NSApp.activate()
            }
            .labelStyle(.iconOnly)
            Button("Apri PoliVerse", systemImage: "arrow.up.forward.app") { open() }
                .labelStyle(.iconOnly)
                .keyboardShortcut("o", modifiers: .command)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var freshnessLine: String {
        if session.useMockData { return String(localized: "Dati di esempio") }
        guard let age = agenda.age else { return String(localized: "In aggiornamento…") }
        let date = Date.now.addingTimeInterval(-age)
        return String(localized: "Aggiornato alle \(date.formatted(date: .omitted, time: .shortened))")
    }

    private func nowCard(_ current: CurrentClass, now: Date) -> some View {
        let event = current.event
        return Button { open(.calendar) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.isOngoing ? "Adesso" : "Prossima")
                            .font(.caption2.weight(.bold)).textCase(.uppercase).opacity(0.9)
                        Text(event.title).font(.headline).lineLimit(2)
                        Text([event.roomLabel, "fino alle \(event.end.formatted(date: .omitted, time: .shortened))"]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).opacity(0.92)
                    }
                    Spacer()
                    Text(timerInterval: now...(current.isOngoing ? event.end : event.start), countsDown: true)
                        .font(.system(size: 24, weight: .black).width(.expanded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if current.isOngoing {
                    ProgressView(value: current.progress(at: now)).tint(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ caption: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.bold)).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }

    private func shortcut(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accedi a PoliVerse per vedere qui le lezioni, gli esami e le novità.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Apri PoliVerse") { open() }
                .buttonStyle(.glassProminent)
        }
        .padding(.vertical, 4)
    }
}

/// A titled group of rows in the panel.
private struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    var badge: Int = 0
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, badge: Int = 0, @ViewBuilder content: () -> Content) {
        self.title = title
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            content
        }
        .padding(4)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
    }
}

/// One row in a panel section.
private struct PanelRow: View {
    let symbol: String
    let title: String
    let detail: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(.rect)
    }
}
#endif
