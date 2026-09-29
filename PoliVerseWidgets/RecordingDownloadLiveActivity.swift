// ActivityKit and the Lock Screen families are iPhone and iPad only.
#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// A recording's download, live on the Lock Screen and in the Dynamic Island.
///
/// The download runs on a background session with the app closed; this is where the
/// student sees it carry on, and learns when the lecture is ready to watch offline.
struct RecordingDownloadLiveActivity: Widget {
    /// The declaration's content.
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingDownloadAttributes.self) { context in
            RecordingDownloadView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: DownloadActivityText.symbol(context.state.phase))
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(DownloadActivityText.figure(context.state))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.course)
                            .font(.headline)
                            .lineLimit(1)
                        DownloadProgressBar(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: DownloadActivityText.symbol(context.state.phase))
            } compactTrailing: {
                Text(DownloadActivityText.figure(context.state))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                DownloadRing(state: context.state)
            }
            .keylineTint(.accentColor)
        }
    }
}

/// The Lock Screen presentation: what is downloading, how far it has got, and how it
/// ended.
struct RecordingDownloadView: View {
    /// The activity's attributes and current state.
    let context: ActivityViewContext<RecordingDownloadAttributes>

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(DownloadActivityText.headline(context.state.phase),
                      systemImage: DownloadActivityText.symbol(context.state.phase))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(DownloadActivityText.figure(context.state))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            Text(context.attributes.course)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(context.attributes.detail)
                if let megabytes = context.attributes.megabytes {
                    Text("·")
                    Text(Measurement(value: Double(megabytes), unit: UnitInformationStorage.megabytes),
                         format: .byteCount(style: .file))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            DownloadProgressBar(state: context.state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The bar: determinate when the size is known, moving otherwise, full when done.
struct DownloadProgressBar: View {
    /// Where the download stands.
    let state: RecordingDownloadAttributes.ContentState

    /// The view's content.
    var body: some View {
        switch state.phase {
        case .downloading:
            if let fraction = state.fraction {
                ProgressView(value: fraction).tint(.accentColor)
            } else {
                ProgressView().progressViewStyle(.linear).tint(.accentColor)
            }
        case .finished:
            ProgressView(value: 1).tint(.green)
        case .interrupted, .failed:
            ProgressView(value: state.fraction ?? 0).tint(.secondary)
        }
    }
}

/// The minimal presentation: a ring filling up, or the outcome's symbol.
struct DownloadRing: View {
    /// Where the download stands.
    let state: RecordingDownloadAttributes.ContentState

    /// The view's content.
    var body: some View {
        if state.phase == .downloading, let fraction = state.fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .tint(.accentColor)
        } else {
            Image(systemName: DownloadActivityText.symbol(state.phase))
        }
    }
}

/// The words and symbols the presentations share.
enum DownloadActivityText {
    /// The symbol for where a download stands.
    static func symbol(_ phase: RecordingDownloadAttributes.ContentState.Phase) -> String {
        switch phase {
        case .downloading: "arrow.down.circle"
        case .finished: "checkmark.circle.fill"
        case .interrupted: "pause.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    /// The line above the title.
    static func headline(_ phase: RecordingDownloadAttributes.ContentState.Phase) -> LocalizedStringKey {
        switch phase {
        case .downloading: "Download della registrazione"
        case .finished: "Registrazione scaricata"
        case .interrupted: "Download interrotto · riprende all'apertura"
        case .failed: "Download non riuscito"
        }
    }

    /// The short figure: the percentage while downloading, a word otherwise.
    static func figure(_ state: RecordingDownloadAttributes.ContentState) -> String {
        switch state.phase {
        case .downloading:
            state.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "…"
        case .finished: String(localized: "Pronta")
        case .interrupted: String(localized: "In pausa")
        case .failed: String(localized: "Errore")
        }
    }
}
#endif
