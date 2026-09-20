import SwiftUI

/// **Opzione E — Cruscotto.** I corsi come avanzamento del semestre.
///
/// Le altre quattro rispondono a "dove vado adesso". Questa risponde a "come
/// sto andando": in cima i numeri su ``FactTiles`` e la ripartizione dei CFU
/// su ``ShareBar`` — gli stessi pezzi con cui sono disegnate le pagine del
/// corso — poi ogni corso con l'anello delle lezioni svolte.
///
/// È la più ricca di informazione e la più a rischio: l'anello vale solo se le
/// lezioni in agenda sono complete, altrimenti mostra numeri falsi con l'aria
/// di essere precisi.
struct CoursesOptionDashboard: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    private var overall: Double {
        guard !courses.isEmpty else { return 0 }
        let weight = courses.reduce(0.0) { $0 + Double(max($1.course.cfu, 1)) }
        return courses.reduce(0.0) { $0 + $1.progress * Double(max($1.course.cfu, 1)) } / weight
    }

    private var credits: Int { courses.reduce(0) { $0 + $1.course.cfu } }

    private var segments: [ShareBar.Segment] {
        courses.map {
            ShareBar.Segment(id: $0.id, title: $0.course.monogram, colour: $0.accent,
                             value: Double(max($0.course.cfu, 1)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Il semestre")
                summary
            }
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Corso per corso")
                VStack(spacing: 10) {
                    ForEach(courses) { brief in
                        Button { open(brief.course) } label: { card(brief) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            FactTiles(facts: [
                (overall.formatted(.percent.precision(.fractionLength(0))), String(localized: "svolto")),
                ("\(courses.count)", String(localized: "corsi")),
                ("\(credits)", String(localized: "CFU")),
                ("\(courses.count { $0.unread > 0 })", String(localized: "con novità")),
            ], tint: style.accent(scheme))

            // La ripartizione dei crediti, con la stessa barra e la stessa
            // legenda delle pagine del corso.
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Peso in crediti")
                ShareBar(segments: segments)
                    .padding(14)
                    .lookCard(cornerRadius: 20)
            }
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
                Text(detail(brief))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            CourseBadge(count: brief.unread)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ brief: CourseBrief) -> String {
        var parts = ["\(brief.course.cfu) CFU"]
        if let when = brief.whenText(locale: locale) { parts.append(when) }
        if let sitting = brief.nextSitting {
            parts.append(String(localized: "appello \(sitting.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("E · Cruscotto") {
    CoursesOptionPreview { CoursesOptionDashboard(courses: CourseBrief.samples) }
}
