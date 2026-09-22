import SwiftUI
import WidgetKit

/// The whole day at a glance: every lecture, exam and deadline, in order,
/// with the ones already over pushed into the background.
///
/// "Prossima lezione" answers *what now*; this answers *what today looks
/// like*, which is the question you ask in the morning and while deciding
/// whether it is worth going in.
struct TodayEntry: TimelineEntry {
    /// The moment this entry describes, which is also the day it shows.
    let date: Date
    /// Everything on that day, in time order.
    let events: [AgendaEvent]
    /// Seconds since the app last wrote the agenda, or `nil` when signed out.
    let age: TimeInterval?
    /// Whether anyone is signed in. Distinct from an empty day: an invitation to sign in and
    /// “nothing scheduled” are different answers.
    let signedIn: Bool

    /// Worth surfacing in the morning, when the day is still ahead.
    var relevance: TimelineEntryRelevance? {
        let hour = Calendar.current.component(.hour, from: date)
        return !events.isEmpty && (6..<10).contains(hour) ? .init(score: 0.7, duration: 3600) : nil
    }
}

/// Builds the day's timeline from the cached agenda.
///
/// An entry is produced at every moment a row changes state — each event's start and end
/// — and once at midnight, when the day this widget is about becomes a different day.
struct TodayProvider: TimelineProvider {
    /// A representative day, for the widget gallery and for redaction.
    ///
    /// - Parameter context: WidgetKit's context.
    /// - Returns: The placeholder entry.
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, events: TodayEntry.previewEvents, age: 0, signedIn: true)
    }

    /// Today as it stands now.
    ///
    /// - Parameters:
    ///   - context: WidgetKit's context.
    ///   - completion: Handed the entry.
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// The day's timeline, capped at twenty entries and reloaded after the last.
    ///
    /// - Parameters:
    ///   - context: WidgetKit's context.
    ///   - completion: Handed the timeline.
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

    /// One entry for a moment, read from the cached agenda.
    ///
    /// - Parameter date: The moment to describe.
    /// - Returns: The entry.
    private func entry(at date: Date) -> TodayEntry {
        let cached = WidgetAgenda.load()
        return TodayEntry(date: date,
                          events: WidgetAgenda.events(on: date, from: cached?.events ?? []),
                          age: cached?.age,
                          signedIn: WidgetAgenda.isSignedIn)
    }
}

/// The Oggi widget: the whole day at a glance, in the medium and large families. Tapping
/// it opens the calendar.
struct TodayWidget: Widget {
    /// The declaration's content.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today.rawValue, provider: TodayProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(AppDestination.calendar.url)
        }
        .configurationDisplayName("Oggi")
        .description("Le lezioni e le scadenze della giornata.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Draws one ``TodayEntry``.
struct TodayView: View {
    /// The day to draw.
    let entry: TodayEntry
    /// The widget family being drawn.
    @Environment(\.widgetFamily) private var family

    /// The large family has room for more rows; the medium one has four lines
    /// before the text starts fighting for space.
    private var limit: Int { family == .systemLarge ? 8 : 4 }

    /// The view's content.
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

    /// The rows that fit this family.
    private var shown: [AgendaEvent] { Array(entry.events.prefix(limit)) }
    /// How many rows did not fit, counted below them.
    private var overflow: Int { max(0, entry.events.count - limit) }

    /// The day's date, with the age of the cache beside it once it is more than half a day
    /// old.
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

    /// One centred line, for a day with nothing on it or an account not signed in.
    ///
    /// - Parameter text: What to say.
    /// - Returns: The filler.
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
    /// The entry this row shows.
    let event: AgendaEvent
    /// The moment the row is drawn for, which decides whether it reads as now or as over.
    let now: Date

    /// Whether the entry has finished.
    private var isOver: Bool { event.end < now }
    /// Whether the entry is under way.
    private var isNow: Bool { event.start <= now && event.end >= now }

    /// The view's content.
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
                if let room = event.roomLabel {
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

/// A representative day, for the gallery and for previews.
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
