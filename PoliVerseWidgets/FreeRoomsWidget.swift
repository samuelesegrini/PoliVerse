import AppIntents
import SwiftUI
import WidgetKit

/// Which campus the widget is about. The only thing worth configuring: a
/// student at Leonardo has no use for Bovisa's rooms, and vice versa.
struct FreeRoomsConfiguration: WidgetConfigurationIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Aule libere"
    /// The intent's subtitle in the Shortcuts library.
    static let description = IntentDescription("Scegli la sede da mostrare.")

    /// The campus to show, or `nil` to fall back to the last one the app wrote.
    @Parameter(title: "Sede", optionsProvider: CampusOptions())
    var campus: String?

    /// Creates an unconfigured intent, as WidgetKit requires.
    init() {}
    /// Creates the intent for one campus.
    ///
    /// - Parameter campus: The campus to show.
    init(campus: String?) { self.campus = campus }
}

/// Offers the campuses the app has actually fetched rooms for.
///
/// Not a hardcoded list: the catalogue names them, they have changed before,
/// and a widget offering a campus with no data would configure into a blank.
struct CampusOptions: DynamicOptionsProvider {
    /// The campuses to offer.
    ///
    /// - Returns: The campuses the app has written a snapshot for. Empty until it has written
    ///   one, so the widget cannot be configured into a blank.
    /// - Throws: Never.
    func results() async throws -> [String] {
        FreeRoomsSnapshot.knownCampuses
    }
}

/// The "Aggiorna" button: fetches the campus again, from the widget.
///
/// Runs in the extension, not the app, and WidgetKit reloads the timeline
/// when `perform()` returns — without charging the reload to the widget's
/// daily budget. So the fetch must be finished, and on disk, before returning.
struct RefreshFreeRoomsIntent: AppIntent {
    /// The intent's name in Siri and the Shortcuts library.
    static let title: LocalizedStringResource = "Aggiorna aule libere"
    /// Whether the intent is offered in the Shortcuts library.
    static let isDiscoverable = false

    /// The campus to refresh.
    @Parameter(title: "Sede")
    var campus: String?

    /// Creates an unconfigured intent, as WidgetKit requires.
    init() {}
    /// Creates the intent for one campus.
    ///
    /// - Parameter campus: The campus to refresh.
    init(campus: String?) { self.campus = campus }

    /// Runs the intent.
    ///
    /// - Returns: An empty result; the intent's effect is the navigation it performs.
    /// - Throws: Nothing in practice.
    func perform() async throws -> some IntentResult {
        if let campus = FreeRoomsProvider.campus(campus) {
            await FreeRoomsProvider.refresh(campus: campus, deadline: .now.addingTimeInterval(20))
        }
        return .result()
    }
}

/// One moment's answer: which rooms are free, and why there is nothing to show.
struct FreeRoomsEntry: TimelineEntry {
    /// The moment this entry describes.
    let date: Date
    /// The campus being shown.
    let campus: String?
    /// The rooms free at ``date``, by name.
    let free: [FreeRoomsSnapshot.Room]
    /// How many rooms the snapshot covers.
    let total: Int
    /// Why there is nothing to show, when there is nothing to show.
    let state: State

    /// `ok` when the question could be answered, `noData` when the app has never written a
    /// snapshot, `staleDay` when the snapshot is another day's, and `closed` outside teaching
    /// hours.
    enum State { case ok, noData, staleDay, closed }

    /// Moderately relevant through the teaching day, when there is an answer.
    var relevance: TimelineEntryRelevance? {
        state == .ok ? .init(score: 0.4, duration: 1800) : nil
    }
}

/// Builds the timeline from the snapshot the app wrote, and fetches one itself when there
/// is none for today.
///
/// Each entry is the same bookings asked a different question — which rooms are free at
/// this time — so a timeline of half-hourly entries costs one read from disk.
struct FreeRoomsProvider: AppIntentTimelineProvider {
    /// A representative campus, for the widget gallery and for redaction.
    ///
    /// - Parameter context: WidgetKit's context.
    /// - Returns: The placeholder entry.
    func placeholder(in context: Context) -> FreeRoomsEntry {
        FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                       free: FreeRoomsSnapshot.previewRooms, total: 96, state: .ok)
    }

    /// The configured campus as it stands now.
    ///
    /// - Parameters:
    ///   - configuration: Which campus the student chose.
    ///   - context: WidgetKit's context.
    /// - Returns: The entry.
    func snapshot(for configuration: FreeRoomsConfiguration, in context: Context) async -> FreeRoomsEntry {
        entry(at: .now, campus: configuration.campus)
    }

    /// Half-hourly entries over the next six hours.
    ///
    /// Today's bookings are fetched first when none are on disk — the one network call a
    /// widget makes on its own — so that a timeline reload every half hour stays a read from
    /// disk.
    ///
    /// - Parameters:
    ///   - configuration: Which campus the student chose.
    ///   - context: WidgetKit's context.
    /// - Returns: The timeline.
    func timeline(for configuration: FreeRoomsConfiguration, in context: Context) async -> Timeline<FreeRoomsEntry> {
        let now = Date.now
        // The one network call a widget makes on its own: only when there is
        // nothing for today, so a timeline reload every half hour stays a
        // read from disk.
        if let campus = Self.campus(configuration.campus), Self.today(campus) == nil {
            await Self.refresh(campus: campus, deadline: now.addingTimeInterval(15))
        }
        let steps = stride(from: 0, through: 6 * 3600, by: 1800)
            .map { now.addingTimeInterval(TimeInterval($0)) }
        let entries = steps.map { entry(at: $0, campus: configuration.campus) }
        return Timeline(entries: entries,
                        policy: .after(steps.last ?? now.addingTimeInterval(1800)))
    }

    /// The campus to show: the configured one, then the last the app wrote, then the first it
    /// knows about.
    ///
    /// - Parameter configured: What the student chose, if anything.
    /// - Returns: The campus, or `nil` when the app has written nothing.
    nonisolated static func campus(_ configured: String?) -> String? {
        configured ?? FreeRoomsSnapshot.lastCampus ?? FreeRoomsSnapshot.knownCampuses.first
    }

    /// The app group's offline store, where the app writes the snapshots.
    nonisolated private static var store: OfflineStore {
        OfflineStore(groupIdentifier: OfflineStore.groupIdentifier)
    }

    /// Today's snapshot for a campus.
    ///
    /// - Parameter campus: The campus to read.
    /// - Returns: The snapshot, or `nil` when none is stored or it is another day's.
    nonisolated static func today(_ campus: String) -> FreeRoomsSnapshot? {
        store.load(FreeRoomsSnapshot.self, as: FreeRoomsSnapshot.cacheName, account: campus)
            .map(\.value)
            .flatMap { $0.covers(.now) ? $0 : nil }
    }

    /// Fetches today's bookings from the widget itself, and waits for the write to land.
    ///
    /// Needs the room list the app publishes, since an extension has no catalogue of its own
    /// and fetching one would be several more requests inside a budget of seconds. Without
    /// it nothing happens and the widget asks for the app.
    ///
    /// A pass in which no room answered is not written: an empty snapshot would read as “no
    /// free rooms”, which is a claim rather than an absence.
    ///
    /// - Parameters:
    ///   - campus: The campus to fetch.
    ///   - deadline: When to stop starting requests.
    nonisolated static func refresh(campus: String, deadline: Date) async {
        guard let refs = store.load([FreeRoomsSnapshot.RoomRef].self,
                                    as: FreeRoomsSnapshot.catalogueCacheName,
                                    account: campus)?.value,
              !refs.isEmpty
        else { return }
        let snapshot = await FreeRoomsSnapshot.fetch(
            campus: campus, rooms: refs, day: .now, deadline: deadline)
        guard !snapshot.rooms.isEmpty else { return }
        let store = store
        store.save(snapshot, as: FreeRoomsSnapshot.cacheName, account: campus)
        await store.flushed()
    }

    /// One entry for a moment, read from the snapshot.
    ///
    /// - Parameters:
    ///   - date: The moment to answer for.
    ///   - campus: The configured campus, if any.
    /// - Returns: The entry, with a ``FreeRoomsEntry/State`` saying why it is empty when it
    ///   is.
    private func entry(at date: Date, campus: String?) -> FreeRoomsEntry {
        let name = Self.campus(campus)
        guard let name,
              let slot = OfflineStore(groupIdentifier: OfflineStore.groupIdentifier)
                  .load(FreeRoomsSnapshot.self, as: FreeRoomsSnapshot.cacheName, account: name)
        else {
            return FreeRoomsEntry(date: date, campus: campus, free: [], total: 0, state: .noData)
        }
        let snapshot = slot.value
        // Yesterday's bookings are not a stale answer to today's question,
        // they are an answer to a different one.
        guard snapshot.covers(date) else {
            return FreeRoomsEntry(date: date, campus: name, free: [], total: 0, state: .staleDay)
        }
        guard Self.isTeachingHours(date) else {
            return FreeRoomsEntry(date: date, campus: name, free: [],
                                  total: snapshot.rooms.count, state: .closed)
        }
        return FreeRoomsEntry(date: date, campus: name,
                              free: snapshot.free(at: date),
                              total: snapshot.rooms.count, state: .ok)
    }

    /// Whether a moment falls in the teaching day.
    ///
    /// Outside 08:00 to 20:00 every room is trivially free, which is true and useless. The
    /// same window the app uses.
    ///
    /// - Parameter date: The moment to test.
    /// - Returns: `true` inside teaching hours.
    private static func isTeachingHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return (8..<20).contains(hour)
    }
}

/// The free-rooms widget, configurable per campus. Tapping it opens the free-rooms
/// screen.
struct FreeRoomsWidget: Widget {
    /// The declaration's content.
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.freeRooms.rawValue,
                               intent: FreeRoomsConfiguration.self,
                               provider: FreeRoomsProvider()) { entry in
            FreeRoomsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(AppDestination.freeRooms.url)
        }
        .configurationDisplayName("Aule libere")
        .description("Le aule libere adesso, nella sede che scegli.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// Draws one ``FreeRoomsEntry``, in whichever family is asked for.
struct FreeRoomsWidgetView: View {
    /// The rooms to draw.
    let entry: FreeRoomsEntry
    /// The widget family being drawn.
    @Environment(\.widgetFamily) private var family

    /// How many rooms this family has room for.
    private var limit: Int { family == .systemMedium ? 6 : 3 }

    /// The view's content.
    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        default: home
        }
    }

    /// The rectangular Lock Screen accessory: the count and the first few names.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Aule libere").font(.headline)
            switch entry.state {
            case .ok:
                Text("\(entry.free.count) di \(entry.total)").font(.caption)
                Text(entry.free.prefix(3).map(\.name).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            default:
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Home Screen families: the count, a refresh button, and a shortlist of rooms — in
    /// two columns at the medium size, where one column of six would be taller than the
    /// widget.
    private var home: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label("Aule libere", systemImage: "building.2")
                    .labelStyle(.titleOnly)
                    .font(.caption2.weight(.semibold))
                Spacer()
                if let campus = entry.campus {
                    Text(campus).font(.caption2).lineLimit(1)
                }
                Button(intent: RefreshFreeRoomsIntent(campus: entry.campus)) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                        .accessibilityLabel("Aggiorna")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            if entry.state == .ok, !entry.free.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.free.count)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("di \(entry.total)").font(.caption2).foregroundStyle(.secondary)
                }
                .invalidatableContent()
                if family == .systemMedium {
                    // Two columns: the useful answer is a shortlist you can
                    // scan, and one column of six is taller than the widget.
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              spacing: 1) {
                        ForEach(entry.free.prefix(limit)) { room in
                            roomLine(room)
                        }
                    }
                } else {
                    ForEach(entry.free.prefix(limit)) { room in
                        roomLine(room)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One room: its name, and its capacity where the catalogue records one.
    ///
    /// - Parameter room: The room to draw.
    /// - Returns: The line.
    private func roomLine(_ room: FreeRoomsSnapshot.Room) -> some View {
        HStack(spacing: 4) {
            Text(room.name).font(.caption.weight(.medium)).lineLimit(1)
            if let seats = room.seats {
                Text("\(seats)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// Four different silences, four different sentences. "Nessuna aula
    /// libera" when the building is shut would be a lie, and when the app has
    /// simply never fetched the campus it would be one too.
    private var message: LocalizedStringKey {
        switch entry.state {
        case .ok: "Nessuna aula libera in questo momento."
        case .noData: "Apri l'app per caricare le aule."
        case .staleDay: "Dati di un altro giorno. Aggiorna o apri l'app."
        case .closed: "Fuori orario di apertura."
        }
    }
}

/// Representative rooms, for the gallery and for previews.
extension FreeRoomsSnapshot {
    /// Only for the placeholder the system renders before real data exists.
    static var previewRooms: [Room] {
        ["3.0.1", "3.1.2", "B.4.1", "Rogers", "L.26.02", "T.1.1"].map {
            Room(id: $0, name: $0, building: "Edificio 3", seats: 120, busy: [])
        }
    }
}
