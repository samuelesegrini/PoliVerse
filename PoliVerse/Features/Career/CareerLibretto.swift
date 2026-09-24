import SwiftUI

/// One academic year of the libretto, or everything still to sit.
///
/// Grouped by year rather than as two flat lists of passed and pending: a
/// list of forty rows sorted by date is a spreadsheet, and says nothing about
/// the first year having gone well and the second having been the hard one,
/// which is the shape a student carries in their head.
///
/// Each year states its own credits and its own average, and a
/// collapsed year still shows its marks as a row of ticks — so the years read
/// against each other at a glance without any of them being opened.
struct LibrettoYearCard: View {
    /// The year's name, or ``StudyPlan/pendingGroup`` for what is still to sit.
    let title: String
    /// The year's entries.
    let exams: [LibrettoExam]
    /// True when the card is open and showing its rows.
    let isExpanded: Bool
    /// Opens or closes the card.
    let toggle: () -> Void

    /// The look in use, which supplies the card's material and colour.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// True for the group of exams still to sit, which has no average of its own.
    private var isPending: Bool { title == StudyPlan.pendingGroup }
    /// The credits passed in this year.
    private var earned: Int { StudyPlan.earnedCFU(of: exams) }
    /// The year's own weighted average, or `nil` when nothing in it is graded.
    private var mean: Double? { StudyPlan.mean(of: exams) }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) { header }
                .buttonStyle(.plain)

            if isExpanded {
                ForEach(exams) { exam in
                    Divider().padding(.leading, 16)
                    LibrettoRow(exam: exam)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard()
    }

    /// The card's title row: the year, its credits and average, its marks as ticks while closed, and the chevron.
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)

            // A collapsed year still says how it went; an open one has the
            // marks themselves two lines below, so the ticks would be saying
            // it twice.
            if !isExpanded, !isPending {
                YearSpark(exams: exams)
            }

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Tocca per chiudere" : "Tocca per aprire")
    }

    /// The line under the year: its credits and average, or how many exams are left to sit.
    private var subtitle: String {
        if isPending {
            let cfu = exams.reduce(0) { $0 + ($1.cfu ?? 0) }
            return cfu > 0
                ? String(localized: "\(exams.count) esami · \(cfu) CFU")
                : String(localized: "\(exams.count) esami")
        }
        let credits = String(localized: "\(earned) CFU")
        guard let mean else { return credits }
        return credits + " · " + String(localized: "media \(mean.formatted(.number.precision(.fractionLength(1))))")
    }
}

/// A year's marks, small enough to sit at the end of its own title row.
private struct YearSpark: View {
    /// The year's entries, whose marks are drawn as ticks.
    let exams: [LibrettoExam]

    /// The look in use, which supplies the ticks' colour.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Up to six, oldest first: past that they stop being legible at this
    /// size and start being texture.
    private var grades: [(id: String, grade: Int)] {
        exams
            .filter { ($0.grade ?? 0) > 0 }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            .suffix(6)
            .map { (id: $0.id, grade: $0.grade ?? 0) }
    }

    /// The view's content.
    var body: some View {
        let grades = grades
        if !grades.isEmpty {
            // The look's ramp, as the chart and every other page of marks
            // uses it, rather than the accent at a hand-picked opacity.
            let tint = FlavorRamp(style: style, scheme: scheme).colour(at: 0.6).color
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(grades, id: \.id) { mark in
                    FigureMetrics.markShape
                        .fill(tint)
                        .frame(width: 4, height: height(of: mark.grade))
                }
            }
            .frame(height: 26, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }

    /// The same 17–30 scale as ``MeanChart``, so a year's ticks and the
    /// chart below read as the same drawing at two sizes.
    private func height(of grade: Int) -> CGFloat {
        max(4, 26 * (Double(grade) - 17) / 13)
    }
}

/// One teaching: the mark if it has been sat, the credits, and when.
///
/// Flat rather than on a card of its own — it lives inside its year's card,
/// separated by rules, because a card per row inside a card is two elevations
/// saying the same thing.
struct LibrettoRow: View {
    /// The entry this row is about.
    let exam: LibrettoExam

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        let accent = style.palette(scheme).accent
        HStack(alignment: .center, spacing: 12) {
            // The mark is the thing being looked for, so it leads.
            Text(exam.displayGrade)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(exam.isPassed ? accent : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(exam.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The line under the name: the credits, and when it was sat or where it stands.
    private var detail: String {
        let credits = (exam.cfu ?? 0) > 0 ? String(localized: "\(exam.cfu ?? 0) CFU") : nil
        let when = exam.date.map {
            $0.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized
        } ?? exam.statusText
        return [credits, when].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Previews

#Preview("Anno") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(StudyPlan(exams: LibrettoExam.samples()).byYear, id: \.year) { group in
                LibrettoYearCard(title: group.year, exams: group.exams,
                                 isExpanded: group.year == StudyPlan.pendingGroup) {}
            }
        }
        .padding(16)
    }
    .previewEnvironment()
}
