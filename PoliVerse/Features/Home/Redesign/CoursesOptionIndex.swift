import SwiftUI

/// **Opzione D — Indice.** Una lista densa, con la ricerca in cima.
///
/// L'opposto della griglia: niente colore per riempire, niente carte grandi.
/// Righe alte 44 punti, un filo di colore a sinistra, il nome, e a destra la
/// sola cosa che cambia. Con venti corsi (fuori corso, altra matricola, corsi
/// singoli) è l'unica delle cinque che non costringe a scorrere per minuti, e
/// la ricerca fa il lavoro che nelle altre fanno i filtri.
struct CoursesOptionIndex: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale
    @State private var query = ""

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
        VStack(alignment: .leading, spacing: 18) {
            search
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .animation(.snappy, value: matching.map(\.id))
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cerca un corso o un docente", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button("Annulla", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .lookCard(cornerRadius: 14)
    }

    private func row(_ brief: CourseBrief, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Il colore c'è, ma come filo verticale: identifica senza
                // prendersi spazio, e sopravvive a righe alte 44 punti.
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
                        .foregroundStyle(brief.isOngoing ? brief.accent : .secondary)
                        .lineLimit(1)
                }
                UnreadDot(count: brief.unread)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            if !last { Divider().padding(.leading, 29) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("D · Indice") {
    ScrollView {
        CoursesOptionIndex(courses: CourseBrief.samples)
            .padding(20)
    }
    .previewEnvironment()
}
