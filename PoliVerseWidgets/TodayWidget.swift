import SwiftUI
import WidgetKit

/// The whole day at a glance: every lecture, exam and deadline, in order,
/// with the ones already over pushed into the background.
///
/// "Prossima lezione" answers *what now*; this answers *what today looks
/// like*, which is the question you ask in the morning and while deciding
/// whether it is worth going in.
struct TodayEntry: TimelineEntry {
    let date: Date
    let events: [AgendaEvent]
    let age: TimeInterval?
    let signedIn: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, events: TodayEntry.previewEvents, age: 0, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let cached = WidgetAgenda.load()
        let today = WidgetAgenda.events(on: now, from: cached?.events ?? [])

        // Redraw when an event starts or ends — that is when a row moves from
        // "next" to "now" to "done" — and once at midnight, when the day this
        // widget is about becomes a different day.
        var moments: Set<Date> = [now]
        for event in today {
            if event.start > now { moments.insert(event.start) }
            if event.end > now { moments.insert(event.end) }
        }
        let midnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        moments.insert(midnight)

        let dates = Array(moments.sorted().prefix(20))
        let entries = dates.map { date in
            TodayEntry(date: date,
                       events: WidgetAgenda.events(on: date, from: cached?.events ?? []),
                       age: cached?.age,
                       signedIn: WidgetAgenda.isSignedIn)
        }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? midnight)))
    }

    private func entry(at date: Date) -> TodayEntry {
        let cached = WidgetAgenda.load()
        return TodayEntry(date: date,
                          events: WidgetAgenda.events(on: date, from: cached?.events ?? []),
                          age: cached?.age,
                          signedIn: WidgetAgenda.isSignedIn)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today.rawValue, provider: TodayProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Oggi")
        .description("Le lezioni e le scadenze della giornata.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    /// The large family has room for more rows; the medium one has four lines
    /// before the text starts fighting for space.
    private var limit: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !entry.signedIn {
                filler("Accedi")
            } else if entry.events.isEmpty {
                filler("Niente in programma")
            } else {
                ForEach(shown) { event in
                    TodayRow(event: event, now: entry.date)
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shown: [AgendaEvent] { Array(entry.events.prefix(limit)) }
    private var overflow: Int { max(0, entry.events.count - limit) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(entry.date, format: .dateTime.weekday(.wide).day().month())
                .font(.caption.weight(.semibold))
            Spacer()
            if let age = entry.age, age > 3600 * 12 {
                Text(Freshness.describe(age))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func filler(_ text: LocalizedStringKey) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One line of the day.
///
/// Split out so the row can be previewed and tuned on its own — the layout
/// that has to survive a four-word title and a twenty-word one is this, not
/// the widget around it.
struct TodayRow: View {
    let event: AgendaEvent
    let now: Date

    private var isOver: Bool { event.end < now }
    private var isNow: Bool { event.start <= now && event.end >= now }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(event.start, style: .time)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)

            // A bar rather than an icon: it reads as "this one is happening"
            // at a glance, which a glyph at caption size does not.
            Capsule()
                .fill(isNow ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.caption.weight(isNow ? .semibold : .regular))
                    .lineLimit(1)
                if let room = event.roomAcronym ?? event.room {
                    Text(room)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        // Past entries stay visible — they are how you tell which part of the
        // day is behind you — but they stop competing with what is left.
        .opacity(isOver ? 0.4 : 1)
    }
}

extension TodayEntry {
    /// Only for the placeholder the system renders before real data exists.
    static var previewEvents: [AgendaEvent] {
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        return [
            AgendaEvent(id: 1, title: "Analisi Matematica 2", start: at(9, 15), end: at(11, 15),
                        kind: .lecture, room: "Aula Rogers", roomAcronym: "R.0.1"),
            AgendaEvent(id: 2, title: "Fisica Sperimentale", start: at(11, 30), end: at(13),
                        kind: .lecture, room: "3.0.1", roomAcronym: "3.0.1"),
            AgendaEvent(id: 3, title: "Laboratorio di Informatica", start: at(14, 15), end: at(17, 15),
                        kind: .lecture, room: "Lab De Castro", roomAcronym: "L.1.2"),
        ]
    }
}
