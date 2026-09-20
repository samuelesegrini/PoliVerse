import Accessibility
import Charts
import SwiftUI

/// The average over time, as a chart you can scrub.
///
/// The figure this replaces drew one bar per exam along an axis of *exam
/// number*, so a three-year gap and a three-day gap looked the same, a bar
/// carried two encodings at once (height for the mark, width for the credits)
/// and nothing on it said which exam any bar was. It was a picture of the
/// data rather than a reading of it.
///
/// Structured as Swift Charts wants it, each channel says one thing:
///
/// - **x is time.** The real dates of the sittings, so the gaps are the gaps.
/// - **y is the mark**, 18 to 30, the scale a student already has in mind.
/// - **The line is the weighted average** as it stood after each exam. This is
///   the answer to "am I going up", which a scatter of marks cannot give.
/// - **Each point is an exam**, sized by its credits — how much it moved the
///   line.
///
/// Dragging selects an exam and says what it was and what the average became.
/// VoiceOver gets the same through ``AXChartDescriptor``, which also makes it
/// playable as an audio graph.
struct MeanChart: View {
    let exams: [LibrettoExam]
    /// The exam under the finger, read by whoever owns the headline.
    @Binding var selection: MeanPoint?
    var height: CGFloat = 150

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    /// Where the finger is, while it is down.
    @State private var scrubbing: Date?
    /// Where it last was.
    @State private var inspected: Date?

    /// Marks run 18 to 30; the domain is opened a little at both ends so a 30
    /// and an 18 are not drawn on the frame of the plot.
    private static let domain = 17.0...31.0

    private var points: [MeanPoint] { MeanPoint.all(in: exams) }

    /// A line needs two points to be a line. With one mark there is no
    /// trajectory to show and the card's own figure already says what it was.
    private var hasTrajectory: Bool { points.count >= 2 }

    private var selected: MeanPoint? { selection }

    private func nearest(_ when: Date?) -> MeanPoint? {
        guard let when else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(when)) < abs($1.date.timeIntervalSince(when))
        }
    }

    var body: some View {
        if hasTrajectory {
            // The look's colour on the line, its own neutral behind it.
            //
            // ``FlavorRamp`` is how the pages with *many* things to tell apart
            // colour them — the storage bars, the search tiles — by spreading
            // them along the Flavor's hue. Two steps of that ramp read as two
            // colours rather than as one reading and its evidence: from a navy
            // look, the deep end came out teal against blue dots. A chart with
            // one series and its backing wants the accent role and the ramp's
            // ``FlavorRamp/neutral``, which is what that neutral is for.
            let ramp = FlavorRamp(style: style, scheme: scheme)
            let palette = style.palette(scheme)
            VStack(alignment: .leading, spacing: 8) {
                chart(palette.accent, ramp: ramp)
                    .frame(height: height)
                    .chartXSelection(value: $scrubbing)
                    .onChange(of: scrubbing) { _, now in
                        // `chartXSelection` clears its binding when the
                        // gesture ends, which would blink the reading away the
                        // instant you lifted your finger off the exam you were
                        // reading. The last one stays until another is picked.
                        if let now { inspected = now }
                        selection = nearest(now ?? inspected)
                    }
                    // One tick as the selection passes onto another exam, the
                    // way a picker ticks: the feedback belongs to the value
                    // changing, not to the finger moving.
                    .sensoryFeedback(.selection, trigger: selected?.id)
                    .accessibilityChartDescriptor(self)
                legend(palette.accent, ramp: ramp)
            }
        }
    }

    // MARK: - The chart

    private func chart(_ line: Color, ramp: FlavorRamp) -> some View {
        // The marks are evidence, not a second series to tell apart: the
        // ramp's neutral is exactly the colour for "plainly not one of the
        // items", and it is checked against the ground the look draws on.
        let marks = ramp.neutral.color
        return Chart {
            ForEach(points) { point in
                // The marks, behind: they are the reason the line moves, not
                // the thing being read.
                PointMark(
                    x: .value("Data", point.date),
                    y: .value("Voto", Double(point.grade))
                )
                .symbolSize(point.symbolSize)
                .foregroundStyle(marks)
                .accessibilityHidden(true)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Data", point.date),
                    y: .value("Media", point.mean)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(line)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
            }

            if let selected {
                RuleMark(x: .value("Selezionato", selected.date))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Data", selected.date),
                    y: .value("Voto", Double(selected.grade))
                )
                .symbolSize(selected.symbolSize)
                .foregroundStyle(line)
                PointMark(
                    x: .value("Data", selected.date),
                    y: .value("Media", selected.mean)
                )
                .symbolSize(60)
                .foregroundStyle(line)
            }
        }
        .chartYScale(domain: Self.domain)
        .chartYAxis {
            // Three values, not a ladder: 18 is the pass mark, 30 the top,
            // and one in between is enough to read a height against.
            AxisMarks(position: .leading, values: [18, 24, 30]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let mark = value.as(Int.self) {
                        Text(verbatim: "\(mark)")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(locale)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartPlotStyle { $0.padding(.top, 6) }
    }

    /// Two series need saying once. A chart legend would put it in a box of
    /// its own; this is one line in the card's own type.
    private func legend(_ line: Color, ramp: FlavorRamp) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle()
                    .fill(ramp.neutral.color)
                    .frame(width: 7, height: 7)
                Text("voti")
            }
            HStack(spacing: 4) {
                FigureRule()
                    .stroke(line, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 2)
                Text("media")
            }
            Spacer(minLength: 0)
            Text("tieni premuto per esplorare")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

// MARK: - Audio graphs and VoiceOver

extension MeanChart: AXChartDescriptorRepresentable {
    /// The chart as VoiceOver reads and plays it.
    ///
    /// Two series, as on screen: the marks and the average they add up to.
    /// This is what replaces the one-sentence summary the old figure carried
    /// — a sentence cannot be scrubbed, and an audio graph can.
    func makeChartDescriptor() -> AXChartDescriptor {
        let points = points
        let dates = points.map(\.date.timeIntervalSince1970)

        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Data dell'esame"),
            range: (dates.min() ?? 0)...(dates.max() ?? 1),
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(.dateTime.month(.wide).year())
        }

        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Voto"),
            range: 18...30,
            gridlinePositions: [18, 24, 30]
        ) { value in
            value.formatted(.number.precision(.fractionLength(1)))
        }

        func series(_ name: String, _ value: (MeanPoint) -> Double) -> AXDataSeriesDescriptor {
            AXDataSeriesDescriptor(
                name: name,
                isContinuous: true,
                dataPoints: points.map { point in
                    AXDataPoint(x: point.date.timeIntervalSince1970,
                                y: value(point),
                                label: point.name)
                })
        }

        return AXChartDescriptor(
            title: String(localized: "Andamento della media"),
            summary: summary,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: [
                series(String(localized: "Voti"), { Double($0.grade) }),
                series(String(localized: "Media"), \.mean),
            ])
    }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "" }
        let change = last.mean - first.mean
        let mean = last.mean.formatted(.number.precision(.fractionLength(1)))
        let direction = switch change {
        case 0.05...: String(localized: "in salita")
        case ...(-0.05): String(localized: "in discesa")
        default: String(localized: "stabile")
        }
        return String(localized: "\(points.count) esami, media \(mean), \(direction) dal primo esame.")
    }
}

// MARK: - The data

/// One exam on the chart: when it was, what it was, and where the average
/// stood once it was recorded.
nonisolated struct MeanPoint: Identifiable, Sendable {
    let id: String
    let name: String
    let date: Date
    let grade: Int
    let hasLode: Bool
    let cfu: Int
    let mean: Double

    var displayGrade: String { hasLode ? "\(grade)L" : String(grade) }
    var credits: String { cfu > 0 ? String(localized: "\(cfu) CFU") : "" }

    /// Credits as the point's area, clamped: a one-credit teaching still has
    /// to be findable under a finger, and a twelve-credit one must not eat
    /// its neighbours.
    var symbolSize: CGFloat { cfu > 0 ? CGFloat(min(max(cfu, 2), 14)) * 9 + 30 : 40 }

    static func all(in exams: [LibrettoExam]) -> [MeanPoint] {
        StudyPlan(exams: exams).progression.compactMap { step in
            guard let date = step.exam.date, let grade = step.exam.grade else { return nil }
            return MeanPoint(id: step.exam.id, name: step.exam.name, date: date,
                             grade: grade, hasLode: step.exam.hasLode,
                             cfu: step.exam.cfu ?? 0, mean: step.mean)
        }
    }
}

// MARK: - Previews

#Preview("Andamento") {
    @Previewable @State var selection: MeanPoint?
    VStack(alignment: .leading) {
        MeanChart(exams: LibrettoExam.samples(), selection: $selection)
    }
    .padding(20)
    .previewEnvironment()
}
