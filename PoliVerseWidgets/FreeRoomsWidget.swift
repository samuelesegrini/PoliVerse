import AppIntents
import SwiftUI
import WidgetKit

/// Which campus the widget is about. The only thing worth configuring: a
/// student at Leonardo has no use for Bovisa's rooms, and vice versa.
struct FreeRoomsConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Aule libere"
    static let description = IntentDescription("Scegli la sede da mostrare.")

    @Parameter(title: "Sede", optionsProvider: CampusOptions())
    var campus: String?

    init() {}
    init(campus: String?) { self.campus = campus }
}

/// Offers the campuses the app has actually fetched rooms for.
///
/// Not a hardcoded list: the catalogue names them, they have changed before,
/// and a widget offering a campus with no data would configure into a blank.
struct CampusOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        FreeRoomsSnapshot.knownCampuses
    }
}

struct FreeRoomsEntry: TimelineEntry {
    let date: Date
    let campus: String?
    let free: [FreeRoomsSnapshot.Room]
    let total: Int
    /// Why there is nothing to show, when there is nothing to show.
    let state: State

    enum State { case ok, noData, staleDay, closed }
}

struct FreeRoomsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FreeRoomsEntry {
        FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                       free: FreeRoomsSnapshot.previewRooms, total: 96, state: .ok)
    }

    func snapshot(for configuration: FreeRoomsConfiguration, in context: Context) async -> FreeRoomsEntry {
        entry(at: .now, campus: configuration.campus)
    }

    /// Recomputed every half hour of the teaching day.
    ///
    /// Nothing is fetched: the bookings for the day are already on disk, so
    /// each entry is the same data asked a different question — "which rooms
    /// are free *at this time*". Half an hour matches the granularity the
    /// timetable itself has.
    func timeline(for configuration: FreeRoomsConfiguration, in context: Context) async -> Timeline<FreeRoomsEntry> {
        let now = Date.now
        let steps = stride(from: 0, through: 6 * 3600, by: 1800)
            .map { now.addingTimeInterval(TimeInterval($0)) }
        let entries = steps.map { entry(at: $0, campus: configuration.campus) }
        return Timeline(entries: entries,
                        policy: .after(steps.last ?? now.addingTimeInterval(1800)))
    }

    private func entry(at date: Date, campus: String?) -> FreeRoomsEntry {
        let name = campus ?? FreeRoomsSnapshot.knownCampuses.first
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

    /// Outside 08:00–20:00 every room is trivially free, which is true and
    /// useless — the building is shut. Same window the app uses.
    private static func isTeachingHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return (8..<20).contains(hour)
    }
}

struct FreeRoomsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.freeRooms.rawValue,
                               intent: FreeRoomsConfiguration.self,
                               provider: FreeRoomsProvider()) { entry in
            FreeRoomsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Aule libere")
        .description("Le aule libere adesso, nella sede che scegli.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct FreeRoomsWidgetView: View {
    let entry: FreeRoomsEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemMedium ? 6 : 3 }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        default: home
        }
    }

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
            }
            .foregroundStyle(.secondary)

            if entry.state == .ok, !entry.free.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.free.count)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("di \(entry.total)").font(.caption2).foregroundStyle(.secondary)
                }
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
        case .staleDay: "Dati di un altro giorno. Apri l'app."
        case .closed: "Fuori orario di apertura."
        }
    }
}

extension FreeRoomsSnapshot {
    /// Only for the placeholder the system renders before real data exists.
    static var previewRooms: [Room] {
        ["3.0.1", "3.1.2", "B.4.1", "Rogers", "L.26.02", "T.1.1"].map {
            Room(id: $0, name: $0, building: "Edificio 3", seats: 120, busy: [])
        }
    }
}
