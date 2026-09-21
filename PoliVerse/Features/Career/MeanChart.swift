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
/// - **The line is the weighted average** as it stood at the end of each day
///   marks were recorded. This is the answer to "am I going up", which a
///   scatter of marks cannot give.
/// - **Each point is an exam**, sized by its credits — how much it moved the
///   line.
///
/// Dragging selects a day and says what was recorded on it and what the
/// average became.
///
/// The line follows days rather than exams because two exams recorded on the
/// same date have no order between them: ``StudyPlan/progression`` sorts by
/// date alone, so "the average after the first of the two" is an artefact of
/// whatever order the libretto happened to return. Per exam, the line drew a
/// vertical segment at one date and only ever one of the two could be put
/// under the finger. Per day, both marks keep their dots and the reading is
/// the one figure that is true: where the average stood once that day was
/// over.
/// VoiceOver gets the same through ``AXChartDescriptor``, which also makes it
/// playable as an audio graph.
struct MeanChart: View {
    let exams: [LibrettoExam]
    /// The day under the finger, read by whoever owns the headline.
    @Binding var selection: MeanDay?
    var height: CGFloat = 150

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    /// Where the finger is, while it is down.
    @State private var scrubbing: Date?
    /// Where it last was.
    @State private var inspected: Date?
    /// What was selected when the current gesture began, and whether the
    /// gesture ever moved onto another exam — together they tell a tap on the
    /// exam already being read (which clears it) from a drag that ends there.
    @State private var beforeGesture: MeanDay.ID?
    @State private var movedOn = false

    /// Marks run 18 to 30; the domain is opened a little at both ends so a 30
    /// and an 18 are not drawn on the frame of the plot.
    private static let domain = 17.0...31.0

    private var points: [MeanPoint] { MeanPoint.all(in: exams) }

    /// The same marks gathered into the days they were recorded on: what the
    /// line is drawn through and what a finger selects.
    private var days: [MeanDay] { MeanDay.all(in: points) }

    /// A line needs two points to be a line. Everything recorded on one day is
    /// one point in time: there is no trajectory to show, and the card's own
    /// figure already says where the average stands.
    private var hasTrajectory: Bool { days.count >= 2 }

    private var selected: MeanDay? { selection }

    private func nearest(_ when: Date?) -> MeanDay? {
        guard let when else { return nil }
        return days.min {
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
                    .onChange(of: scrubbing) { was, now in
                        // `chartXSelection` clears its binding when the
                        // gesture ends, which would blink the reading away the
                        // instant you lifted your finger off the exam you were
                        // reading. The last one stays until another is picked
                        // — or until it is tapped again, which is the way out:
                        // a chart you can only ever select on leaves the page
                        // stuck on one exam with nothing to press.
                        guard let now else {
                            if !movedOn, selection?.id == beforeGesture {
                                selection = nil
                                inspected = nil
                            }
                            return
                        }
                        if was == nil {
                            beforeGesture = selection?.id
                            movedOn = false
                        }
                        let point = nearest(now)
                        if point?.id != beforeGesture { movedOn = true }
                        inspected = now
                        selection = point
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

            ForEach(days) { day in
                LineMark(
                    x: .value("Data", day.date),
                    y: .value("Media", day.mean)
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
                // Every mark recorded that day lights up, not one of them:
                // the rule covers the whole date, so picking one dot out of
                // two sitting on it would be a lie about what is selected.
                ForEach(selected.exams) { exam in
                    PointMark(
                        x: .value("Data", exam.date),
                        y: .value("Voto", Double(exam.grade))
                    )
                    .symbolSize(exam.symbolSize)
                    .foregroundStyle(line)
                }
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
            Text(selected == nil ? "tieni premuto per esplorare" : "tocca di nuovo per chiudere")
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

        // The marks are read one exam at a time; the average is read one day
        // at a time, as it is drawn — two exams on a date give VoiceOver two
        // marks and one figure, which is what there is.
        let marks = AXDataSeriesDescriptor(
            name: String(localized: "Voti"),
            isContinuous: true,
            dataPoints: points.map { point in
                AXDataPoint(x: point.date.timeIntervalSince1970,
                            y: Double(point.grade),
                            label: point.name)
            })
        let mean = AXDataSeriesDescriptor(
            name: String(localized: "Media"),
            isContinuous: true,
            dataPoints: days.map { day in
                AXDataPoint(x: day.date.timeIntervalSince1970,
                            y: day.mean,
                            label: day.title)
            })

        return AXChartDescriptor(
            title: String(localized: "Andamento della media"),
            summary: summary,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: [marks, mean])
    }

    private var summary: String {
        guard let first = days.first, let last = days.last else { return "" }
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

/// A day marks were recorded on: everything registered that date, and where
/// the average stood once all of it was.
///
/// The unit the chart is read in. Exams sat on the same day have no order
/// between them — ``StudyPlan/progression`` sorts by date alone — so the
/// averages *between* them are an accident of the libretto's own ordering and
/// are not shown. What is true, and what this carries, is the figure the day
/// left behind.
nonisolated struct MeanDay: Identifiable, Sendable {
    /// The start of the day, which is also its place on the axis.
    let id: Date
    let date: Date
    /// In the order they were recorded, at least one.
    let exams: [MeanPoint]
    /// The weighted average over everything up to the end of this day.
    let mean: Double

    var isSingle: Bool { exams.count == 1 }

    /// The teachings, for the caption and for VoiceOver.
    var title: String {
        exams.map(\.name).joined(separator: " · ")
    }

    /// The marks, in the same order as the names.
    var marks: String {
        exams.map(\.displayGrade).joined(separator: " · ")
    }

    var cfu: Int { exams.reduce(0) { $0 + $1.cfu } }

    var credits: String { cfu > 0 ? String(localized: "\(cfu) CFU") : "" }

    /// Groups marks into their days, keeping the progression's order.
    ///
    /// The day's average is the last step's, not the first's: the steps are
    /// cumulative, so the last one already counts every mark of that day.
    static func all(in points: [MeanPoint], calendar: Calendar = .current) -> [MeanDay] {
        var days: [MeanDay] = []
        for point in points {
            let start = calendar.startOfDay(for: point.date)
            if let last = days.last, last.id == start {
                days[days.count - 1] = MeanDay(id: start, date: last.date,
                                               exams: last.exams + [point], mean: point.mean)
            } else {
                days.append(MeanDay(id: start, date: point.date, exams: [point], mean: point.mean))
            }
        }
        return days
    }
}

// MARK: - Previews

#Preview("Andamento") {
    @Previewable @State var selection: MeanDay?
    VStack(alignment: .leading) {
        MeanChart(exams: LibrettoExam.samples(), selection: $selection)
    }
    .padding(20)
    .previewEnvironment()
}
