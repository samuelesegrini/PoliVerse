import SwiftUI

/// **Opzione E — Cruscotto.** I corsi come avanzamento del semestre.
///
/// Le altre quattro rispondono a "dove vado adesso". Questa risponde a "come
/// sto andando": in cima una barra con il semestre consumato, poi ogni corso
/// con l'anello delle lezioni svolte, i CFU e le novità. È la più ricca di
/// informazione e la più a rischio: l'anello vale solo se le lezioni in agenda
/// sono complete, altrimenti mostra numeri falsi con l'aria di essere precisi.
struct CoursesOptionDashboard: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale

    private var overall: Double {
        guard !courses.isEmpty else { return 0 }
        let weight = courses.reduce(0.0) { $0 + Double(max($1.course.cfu, 1)) }
        return courses.reduce(0.0) { $0 + $1.progress * Double(max($1.course.cfu, 1)) } / weight
    }

    private var credits: Int { courses.reduce(0) { $0 + $1.course.cfu } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            summary
            LookHeading("Corso per corso")
            VStack(spacing: 10) {
                ForEach(courses) { brief in
                    Button { open(brief.course) } label: { card(brief) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(overall, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("del semestre")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            // Una barra per corso, larga in proporzione ai suoi CFU: si vede
            // subito quale materia pesa e quale è rimasta indietro.
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(courses) { brief in
                        let share = Double(max(brief.course.cfu, 1)) / Double(max(credits, 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(brief.accent.opacity(0.18))
                            Capsule().fill(brief.accent)
                                .frame(width: max(3, (geometry.size.width * share - 3) * brief.progress))
                        }
                        .frame(width: max(6, geometry.size.width * share - 3))
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 18) {
                stat("\(courses.count)", "corsi")
                stat("\(credits)", "CFU")
                stat("\(courses.count { $0.unread > 0 })", "con novità")
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func card(_ brief: CourseBrief) -> some View {
        HStack(spacing: 14) {
            ProgressRing(value: brief.progress, tint: brief.accent, lineWidth: 3.5) {
                Text(brief.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(brief.accent)
                    .frame(width: 34, height: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(brief.course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("\(brief.course.cfu) CFU")
                    if let when = brief.whenText(locale: locale) {
                        Text("·")
                        Text(when)
                    }
                    if let sitting = brief.nextSitting {
                        Text("·")
                        Text("appello \(sitting.formatted(.dateTime.day().month(.abbreviated).locale(locale)))")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)
            UnreadDot(count: brief.unread)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

#Preview("E · Cruscotto") {
    ScrollView {
        CoursesOptionDashboard(courses: CourseBrief.samples)
            .padding(20)
    }
    .previewEnvironment()
}
