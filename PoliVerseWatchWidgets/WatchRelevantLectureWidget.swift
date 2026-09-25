import AppIntents
import RelevanceKit
import SwiftUI
import WidgetKit

/// Which lecture a Smart Stack card is about.
///
/// Never shown to the student: the system makes one of these per lecture from
/// ``WatchRelevantLectureProvider/relevance()``, and a card is the lecture it
/// names. `nil` means "whatever is on or next", for the card raised by place
/// rather than by time.
struct WatchLectureIntent: WidgetConfigurationIntent {
    /// The intent's name.
    static let title: LocalizedStringResource = "Lezione"
    /// Made by the system from the relevance list, never by hand.
    static let isDiscoverable = false

    /// The lecture's identity, from ``WatchSnapshot/Entry/id``.
    @Parameter(title: "Lezione")
    var entryID: Int?

    /// Creates an intent for whatever is on or next.
    init() {}

    /// Creates an intent for one lecture.
    ///
    /// - Parameter entryID: The lecture, or `nil` for whatever is on or next.
    init(entryID: Int?) {
        self.entryID = entryID
    }
}

/// What a Smart Stack card draws.
struct WatchRelevantLectureEntry: RelevanceEntry {
    /// The lecture, or `nil` when it is no longer in the snapshot.
    let lecture: WatchSnapshot.Entry?
}

/// Tells watchOS when each lecture is worth a card, and draws the card.
///
/// Two kinds of relevance, which is what `RelevanceConfiguration` exists for:
/// each lecture from a quarter of an hour before it until it ends, and — while
/// there is still something left today — whenever the Watch knows the student
/// is at school, so the next room is one raise away in the corridor.
struct WatchRelevantLectureProvider: RelevanceEntriesProvider {
    /// When each card is relevant.
    func relevance() async -> WidgetRelevance<WatchLectureIntent> {
        guard let snapshot = WatchSnapshotStore.load() else { return WidgetRelevance([]) }
        let now = Date.now
        var attributes = snapshot.entries.filter { $0.end > now }.map {
            WidgetRelevanceAttribute(
                configuration: WatchLectureIntent(entryID: $0.id),
                context: .date(interval: DateInterval(start: $0.start.addingTimeInterval(-15 * 60), end: $0.end),
                               kind: .scheduled))
        }
        if snapshot.entries(on: now).contains(where: { $0.end > now }) {
            attributes.append(WidgetRelevanceAttribute(
                configuration: WatchLectureIntent(entryID: nil),
                context: .location(inferred: .school)))
        }
        return WidgetRelevance(attributes)
    }

    /// The card for one configuration.
    func entry(configuration: WatchLectureIntent, context: Context) async throws -> WatchRelevantLectureEntry {
        if context.isPreview { return WatchRelevantLectureEntry(lecture: .sample) }
        let snapshot = WatchSnapshotStore.load()
        let lecture = configuration.entryID.flatMap { id in snapshot?.entries.first { $0.id == id } }
            ?? snapshot?.current(at: .now)
        return WatchRelevantLectureEntry(lecture: lecture)
    }

    /// What the card shows while the real entry loads.
    func placeholder(context: Context) -> WatchRelevantLectureEntry {
        WatchRelevantLectureEntry(lecture: .sample)
    }
}

/// The Smart Stack card that comes up by itself before each lecture and at
/// the university.
struct WatchRelevantLectureWidget: Widget {
    /// The declaration's content.
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.relevantLecture,
                               provider: WatchRelevantLectureProvider()) { entry in
            WatchRelevantLectureCard(lecture: entry.lecture)
                .containerBackground((entry.lecture?.isExam == true ? Color.red : .accentColor).gradient,
                                     for: .widget)
                .widgetURL(entry.lecture?.url)
        }
        .configurationDisplayName("Lezioni")
        .description("Ogni lezione nello Smart Stack, quando sta per iniziare.")
    }
}

/// The card's content.
///
/// A relevance entry has no timeline, and a widget does not redraw on a clock
/// of its own, so nothing here decides "adesso" at render time. The times say
/// when, and the bar — which the system animates — says how far through.
struct WatchRelevantLectureCard: View {
    /// The lecture, if still known.
    let lecture: WatchSnapshot.Entry?

    /// The view's content.
    var body: some View {
        if let lecture {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: lecture.symbol)
                    Text("\(lecture.start.formatted(date: .omitted, time: .shortened))–\(lecture.end.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                    if let room = lecture.room, !room.isEmpty {
                        Text("· \(room)").lineLimit(1)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                Text(lecture.title)
                    .font(.headline)
                    .lineLimit(2)
                ProgressView(timerInterval: lecture.start...lecture.end, countsDown: false)
                    .labelsHidden()
                    .tint(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Label("Niente in programma", systemImage: "checkmark.circle")
                .font(.headline)
        }
    }
}
