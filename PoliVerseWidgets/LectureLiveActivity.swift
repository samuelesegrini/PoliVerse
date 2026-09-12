import ActivityKit
import SwiftUI
import WidgetKit

/// The lecture, live on the Lock Screen and in the Dynamic Island.
struct LectureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LectureActivityAttributes.self) { context in
            LectureActivityView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.room ?? "—", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(2)
                        ProgressView(timerInterval: range(context), countsDown: false)
                            .tint(.accentColor)
                            .labelsHidden()
                    }
                }
            } compactLeading: {
                Image(systemName: "person.bubble")
            } compactTrailing: {
                countdown(context)
                    .monospacedDigit()
                    // Without this the compact region reserves room for the
                    // widest string the timer could ever produce, and the
                    // island stays stretched for a lecture that is minutes
                    // away.
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "person.bubble")
            }
            .keylineTint(.accentColor)
        }
    }

    private func countdown(_ context: ActivityViewContext<LectureActivityAttributes>) -> Text {
        if context.state.phase == .ended { return Text("Finita") }
        return Text(timerInterval: range(context), countsDown: true)
    }

    /// The interval the countdown and the bar describe.
    ///
    /// `Text(timerInterval:)` ticks on its own, without a push or a timeline
    /// reload — which is the only way a Live Activity can show a live
    /// countdown at all, since an activity gets no periodic refresh of its
    /// own.
    private func range(_ context: ActivityViewContext<LectureActivityAttributes>) -> ClosedRange<Date> {
        let deadline = context.attributes.deadline(for: context.state.phase)
        let from = context.state.phase == .upcoming
            ? min(.now, deadline) : context.attributes.start
        return from...max(from, deadline)
    }
}

struct LectureActivityView: View {
    let context: ActivityViewContext<LectureActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(2)
                if let location = context.attributes.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if context.state.phase == .ended {
                    Text("Finita").font(.title3.weight(.semibold))
                } else {
                    Text(timerInterval: interval, countsDown: true)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                Text(context.attributes.end, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headline: LocalizedStringKey {
        switch context.state.phase {
        case .upcoming: "Inizia tra"
        case .running: "In corso · finisce tra"
        case .ended: "Lezione"
        }
    }

    private var interval: ClosedRange<Date> {
        let deadline = context.attributes.deadline(for: context.state.phase)
        let from = context.state.phase == .upcoming
            ? min(.now, deadline) : context.attributes.start
        return from...max(from, deadline)
    }
}
