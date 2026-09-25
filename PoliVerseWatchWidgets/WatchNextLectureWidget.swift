import RelevanceKit
import SwiftUI
import WidgetKit

/// One moment of the complication's timeline.
struct WatchLectureEntry: TimelineEntry {
    /// When the face starts showing this.
    let date: Date
    /// The lecture on at ``date``, or the next one; `nil` when nothing is left.
    let lecture: WatchSnapshot.Entry?
}

/// Builds the complication's timeline from the kept snapshot.
///
/// One entry per start and end in the snapshot: between two of them nothing
/// the face shows changes, and the countdowns inside each entry tick by
/// themselves.
struct WatchNextLectureProvider: TimelineProvider {
    /// A timeline cannot be arbitrarily long; three days of lectures fit well
    /// inside this.
    private let limit = 48

    /// What the face shows while the real entry loads.
    func placeholder(in context: Context) -> WatchLectureEntry {
        WatchLectureEntry(date: .now, lecture: .sample)
    }

    /// What the face gallery shows.
    func getSnapshot(in context: Context, completion: @escaping (WatchLectureEntry) -> Void) {
        let lecture = WatchSnapshotStore.load()?.current(at: .now)
        completion(WatchLectureEntry(date: .now, lecture: lecture ?? (context.isPreview ? .sample : nil)))
    }

    /// The day ahead, one entry per change.
    ///
    /// Ends with `.never` rather than a guess at a refresh time: the only
    /// thing that makes a new timeline worth drawing is a new snapshot, and
    /// the Watch app reloads the timeline when one arrives.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchLectureEntry>) -> Void) {
        guard let snapshot = WatchSnapshotStore.load() else {
            completion(Timeline(entries: [WatchLectureEntry(date: .now, lecture: nil)], policy: .never))
            return
        }
        let now = Date.now
        let dates = [now] + snapshot.changes(after: now).prefix(limit - 1)
        let entries = dates.map { WatchLectureEntry(date: $0, lecture: snapshot.current(at: $0)) }
        completion(Timeline(entries: entries, policy: .never))
    }

    /// When the Smart Stack should raise the complication's card: from a
    /// quarter of an hour before each lecture until it ends.
    func relevance() async -> WidgetRelevance<Void> {
        guard let snapshot = WatchSnapshotStore.load() else { return WidgetRelevance([]) }
        let now = Date.now
        return WidgetRelevance(snapshot.entries.filter { $0.end > now }.map {
            WidgetRelevanceAttribute(context: .date(
                interval: DateInterval(start: $0.start.addingTimeInterval(-15 * 60), end: $0.end),
                kind: .scheduled))
        })
    }
}

/// The complication: the lecture on now, or the next one, on any face.
struct WatchNextLectureWidget: Widget {
    /// The declaration's content.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.nextLecture, provider: WatchNextLectureProvider()) { entry in
            WatchNextLectureView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .widgetURL(entry.lecture?.url)
        }
        .configurationDisplayName("Prossima lezione")
        .description("La lezione in corso o la prossima, con l'aula.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// The complication in each family.
struct WatchNextLectureView: View {
    /// The timeline entry being drawn.
    let entry: WatchLectureEntry

    /// The family the face placed it in.
    @Environment(\.widgetFamily) private var family

    /// The view's content.
    var body: some View {
        if let lecture = entry.lecture {
            let isOn = lecture.isOn(at: entry.date)
            switch family {
            case .accessoryCircular: circular(lecture, isOn: isOn)
            case .accessoryCorner: corner(lecture, isOn: isOn)
            case .accessoryInline: inline(lecture, isOn: isOn)
            default: WatchLectureRectangle(lecture: lecture, isOn: isOn)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Niente in programma")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label("PoliVerse", systemImage: "checkmark.circle")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Niente in programma")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .widgetLabel("PoliVerse")
            }
        }
    }

    /// A ring that fills through the lecture, or the start time before it.
    private func circular(_ lecture: WatchSnapshot.Entry, isOn: Bool) -> some View {
        Group {
            if isOn {
                ProgressView(timerInterval: lecture.start...lecture.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: lecture.symbol)
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else {
                VStack(spacing: 0) {
                    Image(systemName: lecture.symbol)
                        .font(.caption2)
                        .widgetAccentable()
                    Text(lecture.start.formatted(.dateTime.hour().minute()))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .accessibilityLabel(Text("\(lecture.title), \(lecture.start.formatted(date: .omitted, time: .shortened))"))
    }

    /// The symbol in the corner, the time and room along the bezel.
    private func corner(_ lecture: WatchSnapshot.Entry, isOn: Bool) -> some View {
        Image(systemName: lecture.symbol)
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                if isOn {
                    ProgressView(timerInterval: lecture.start...lecture.end, countsDown: false)
                } else {
                    Text("\(lecture.start.formatted(.dateTime.hour().minute())) \(lecture.room ?? lecture.title)")
                }
            }
    }

    /// One line above the time.
    private func inline(_ lecture: WatchSnapshot.Entry, isOn: Bool) -> some View {
        let place = lecture.room ?? lecture.title
        return isOn
            ? Text("fino \(lecture.end.formatted(.dateTime.hour().minute())) · \(place)")
            : Text("\(lecture.start.formatted(.dateTime.hour().minute())) · \(place)")
    }
}

/// The rectangular complication: what, where, and when.
struct WatchLectureRectangle: View {
    /// The lecture.
    let lecture: WatchSnapshot.Entry
    /// Whether it is under way at the moment being drawn.
    let isOn: Bool

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: lecture.symbol)
                Text(isOn
                     ? String(localized: "Adesso · fino alle \(lecture.end.formatted(date: .omitted, time: .shortened))")
                     : lecture.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(lecture.isExam ? .red : .accentColor)
            .widgetAccentable()
            Text(lecture.title)
                .font(.headline)
                .lineLimit(1)
            if isOn {
                ProgressView(timerInterval: lecture.start...lecture.end, countsDown: false)
                    .labelsHidden()
                    .tint(lecture.isExam ? .red : .accentColor)
            } else if let room = lecture.room, !room.isEmpty {
                Label(room, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Rettangolare", as: .accessoryRectangular) {
    WatchNextLectureWidget()
} timeline: {
    WatchLectureEntry(date: .now, lecture: .sample)
    WatchLectureEntry(date: .now, lecture: nil)
}

#Preview("Circolare", as: .accessoryCircular) {
    WatchNextLectureWidget()
} timeline: {
    WatchLectureEntry(date: .now, lecture: .sample)
}
