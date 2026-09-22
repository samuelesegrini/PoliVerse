import ActivityKit
import SwiftUI
import WidgetKit

/// The lecture, live on the Lock Screen and in the Dynamic Island.
struct LectureLiveActivity: Widget {
    /// The declaration's content.
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
                Image(systemName: context.attributes.symbol)
            } compactTrailing: {
                countdown(context)
                    .monospacedDigit()
                    // Without this the compact region reserves room for the
                    // widest string the timer could ever produce, and the
                    // island stays stretched for a lecture that is minutes
                    // away.
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.attributes.symbol)
            }
            .keylineTint(.accentColor)
        }
    }

    /// The Dynamic Island's countdown, or a word once the lecture is over.
    ///
    /// - Parameter context: The activity's attributes and current state.
    /// - Returns: A self-ticking timer, which needs no push or timeline reload.
    private func countdown(_ context: ActivityViewContext<LectureActivityAttributes>) -> Text {
        if context.state.phase == .ended {
            return context.attributes.kind == .exam ? Text("Finito") : Text("Finita")
        }
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

/// The Lock Screen presentation: the lecture's name, where it is, and how long until it
/// starts or ends.
struct LectureActivityView: View {
    /// The activity's attributes and current state.
    let context: ActivityViewContext<LectureActivityAttributes>

    /// The view's content.
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
                    Text(context.attributes.kind == .exam ? "Finito" : "Finita")
                        .font(.title3.weight(.semibold))
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

    /// What the countdown is counting to, in words, for the current phase and
    /// the kind being followed.
    ///
    /// An exam's running phase says the end is an estimate: the sitting's own
    /// length is never published, so the three hours the activity counts
    /// through are an assumption and should not read as a fact.
    private var headline: LocalizedStringKey {
        switch (context.attributes.kind, context.state.phase) {
        case (.lecture, .upcoming): "Inizia tra"
        case (.lecture, .running): "In corso · finisce tra"
        case (.lecture, .ended): "Lezione"
        case (.exam, .upcoming): "Esame tra"
        case (.exam, .running): "In corso · circa"
        case (.exam, .ended): "Esame"
        }
    }

    /// The span the countdown and the progress bar describe.
    ///
    /// Before the lecture it runs from now to the start; afterwards from the start to the
    /// end. Clamped so the range can never be inverted.
    private var interval: ClosedRange<Date> {
        let deadline = context.attributes.deadline(for: context.state.phase)
        let from = context.state.phase == .upcoming
            ? min(.now, deadline) : context.attributes.start
        return from...max(from, deadline)
    }
}
