import SwiftUI

/// A continuous, round-ended stroke that advances at verified linking milestones.
/// It never fills on a timer while a server is still deciding the outcome.
struct JourneyLinkProgressStyle: ProgressViewStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        ZStack {
            Circle().stroke(JourneyInk.ink.opacity(0.16), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(JourneyInk.action, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.45), value: fraction)
        }
        .padding(3)
        .frame(width: 30, height: 30)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent))
    }
}
