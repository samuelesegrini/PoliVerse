import SwiftUI
import WidgetKit

/// The next lecture: when, where, and how long until it starts.
///
/// The one thing worth glancing at between classes, so it is offered on the
/// Lock Screen as well as the Home Screen.
struct NextLectureEntry: TimelineEntry {
    let date: Date
    let lecture: AgendaEvent?
    /// The one after it, for the medium layout.
    let following: AgendaEvent?
    /// How old the cached timetable is, so the widget can be honest when it is
    /// showing something stale.
    let age: TimeInterval?
    let signedIn: Bool
}

struct NextLectureProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextLectureEntry {
        NextLectureEntry(date: .now, lecture: .preview, following: nil,
                         age: 0, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLectureEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Refreshes at each lecture boundary rather than on a timer.
    ///
    /// A widget gets a small budget of reloads per day; spending it on a fixed
    /// interval wastes most of them on nothing changing. The moments that
    /// matter are when a lecture starts and when it ends, because that is when
    /// the answer to "what's next" changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLectureEntry>) -> Void) {
        let now = Date.now
        let events = WidgetAgenda.load()?.events ?? []
        var dates: [Date] = [now]

        for event in events where event.end > now {
            dates.append(event.start)
            dates.append(event.end)
        }
        // A handful of boundaries is plenty; the timeline is rebuilt long
        // before a distant one is reached.
        let moments = Array(Set(dates).sorted().prefix(12))
        let entries = moments.map { entry(at: $0, events: events) }

        // Reload after the last boundary, or in an hour if there is nothing
        // scheduled — an empty week should not stop the widget updating when
        // the app next fetches.
        let next = moments.last.map { max($0, now.addingTimeInterval(3600)) }
            ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func entry(at date: Date, events: [AgendaEvent]? = nil) -> NextLectureEntry {
        let cached = WidgetAgenda.load()
        let all = events ?? cached?.events ?? []
        let upcoming = all
            .filter { $0.end > date && $0.kind == .lecture }
            .sorted { $0.start < $1.start }
        return NextLectureEntry(
            date: date,
            lecture: upcoming.first,
            following: upcoming.dropFirst().first,
            age: cached?.age,
            signedIn: WidgetAgenda.isSignedIn)
    }

}

struct NextLectureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextLecture.rawValue, provider: NextLectureProvider()) { entry in
            NextLectureView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prossima lezione")
        .description("Quando e dove inizia la prossima lezione.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextLectureView: View {
    let entry: NextLectureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: - Lock Screen

    private var inline: some View {
        if let lecture = entry.lecture {
            Text("\(lecture.start, style: .time) · \(lecture.roomAcronym ?? lecture.room ?? lecture.title)")
        } else {
            Text(emptyLine)
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let lecture = entry.lecture {
                VStack(spacing: 0) {
                    Image(systemName: "person.bubble").font(.caption2)
                    Text(lecture.start, style: .time).font(.caption2).minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: "checkmark").font(.title3)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let lecture = entry.lecture {
                Text(lecture.title).font(.headline).lineLimit(1)
                Text(countdown(to: lecture)).font(.caption)
                if let room = lecture.room ?? lecture.roomAcronym {
                    Text(room).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text(emptyLine).font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Prossima lezione", systemImage: "person.bubble")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleOnly)

            if let lecture = entry.lecture {
                Text(lecture.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Text(lecture.start, style: .time).font(.title3.weight(.bold)).monospacedDigit()
                if let room = lecture.room ?? lecture.roomAcronym {
                    Text(room).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Spacer(minLength: 0)
                Text(emptyLine).font(.subheadline)
                Spacer(minLength: 0)
            }
            staleNote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            if let following = entry.following {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Poi").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(following.title).font(.caption).lineLimit(2)
                    Text(following.start, style: .time).font(.caption.weight(.semibold))
                    if let room = following.room ?? following.roomAcronym {
                        Text(room).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Bits

    /// Signed out and "nothing scheduled" are different answers, and a widget
    /// that shows the second when it means the first is simply wrong.
    private var emptyLine: String {
        entry.signedIn
            ? String(localized: "Niente in programma")
            : String(localized: "Accedi")
    }

    private func countdown(to lecture: AgendaEvent) -> String {
        if lecture.start <= entry.date {
            return String(localized: "In corso · fino alle \(lecture.end.formatted(date: .omitted, time: .shortened))")
        }
        return lecture.start.formatted(date: .omitted, time: .shortened)
    }

    /// Only when it matters. A widget reading from a cache should say so when
    /// the cache is old, and stay quiet when it is not — a permanent "updated
    /// 3 minutes ago" is noise nobody reads.
    @ViewBuilder
    private var staleNote: some View {
        if let age = entry.age, age > 3600 * 12 {
            Text(Freshness.describe(age))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension AgendaEvent {
    /// Only for the placeholder the system renders before real data exists.
    static var preview: AgendaEvent {
        AgendaEvent(id: 1, title: "Analisi Matematica 2",
                    start: .now.addingTimeInterval(1800),
                    end: .now.addingTimeInterval(9000),
                    kind: .lecture, room: "3.0.1", roomAcronym: "3.0.1")
    }
}
