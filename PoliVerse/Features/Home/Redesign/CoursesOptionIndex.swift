import SwiftUI

/// **Opzione D — Indice.** Una lista densa, con la ricerca della barra.
///
/// L'opposto della griglia: niente colore per riempire, niente carte grandi.
/// Righe basse, un filo di colore a sinistra, il nome, e a destra la sola cosa
/// che cambia. Con venti corsi (fuori corso, altra matricola, corsi singoli) è
/// l'unica delle cinque che non costringe a scorrere per minuti.
///
/// La ricerca non è un campo disegnato qui dentro: è la `searchable` della
/// pagina, come in Manifesto e in Aule, così si comporta come ovunque nell'app
/// — la tastiera, l'annulla e lo scorrimento li dà il sistema.
struct CoursesOptionIndex: View {
    let courses: [CourseBrief]
    /// Quello che lo studente ha scritto nella barra di ricerca della pagina.
    var query: String = ""
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale

    private var matching: [CourseBrief] {
        guard !query.isEmpty else { return courses }
        return courses.filter {
            $0.course.name.localizedCaseInsensitiveContains(query)
                || $0.course.teacher.localizedCaseInsensitiveContains(query)
        }
    }

    /// Oggi, poi questa settimana, poi il resto: tre gruppi, non di più.
    private var groups: [(title: LocalizedStringKey, items: [CourseBrief])] {
        let list = matching.sorted { ($0.nextLecture ?? .distantFuture) < ($1.nextLecture ?? .distantFuture) }
        let week = Date.now.addingTimeInterval(7 * 86_400)
        return [
            ("Oggi", list.filter(\.isToday)),
            ("Questa settimana", list.filter { !$0.isToday && ($0.nextLecture.map { $0 < week } ?? false) }),
            ("Gli altri", list.filter { !$0.isToday && !($0.nextLecture.map { $0 < week } ?? false) }),
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 10) {
                    LookHeading(group.title)
                    VStack(spacing: 0) {
                        ForEach(group.items) { brief in
                            Button { open(brief.course) } label: {
                                row(brief, last: brief.id == group.items.last?.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .lookCard()
                }
            }
            if matching.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .lookCard()
            }
        }
        .animation(.snappy, value: matching.map(\.id))
    }

    private func row(_ brief: CourseBrief, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Il colore c'è, ma come filo verticale: identifica senza
                // prendersi spazio, e sopravvive a una riga bassa.
                Capsule().fill(brief.accent).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(brief.course.name)
                        .font(.subheadline.weight(brief.unread > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(brief.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let when = brief.whenText(locale: locale) {
                    Text(when)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(brief.isOngoing ? AnyShapeStyle(brief.accent) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                CourseBadge(count: brief.unread)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            if !last { CardDivider(inset: 29) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("D · Indice") {
    CoursesOptionPreview { CoursesOptionIndex(courses: CourseBrief.samples) }
}
