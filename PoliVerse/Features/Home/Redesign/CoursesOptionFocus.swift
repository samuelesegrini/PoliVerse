import SwiftUI

/// **Opzione C — Focus.** Un corso alla volta, raccontato per intero.
///
/// Prende sul serio l'idea che di solito un corso solo è quello "attivo": la
/// carta in evidenza lo racconta — lezione, aula, appello, novità — con le
/// righe di ``CardRow``, e i monogrammi sotto servono a cambiarlo senza
/// lasciare la pagina. Sotto, un elenco minimo per arrivare comunque a tutto.
/// È la pagina che fa più bella figura con pochi corsi e che regge peggio la
/// crescita: a dodici corsi la fila dei monogrammi è un nastro da scorrere
/// alla cieca.
struct CoursesOptionFocus: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale
    @State private var selection: String?

    private var ordered: [CourseBrief] {
        courses.sorted { ($0.nextLecture ?? .distantFuture) < ($1.nextLecture ?? .distantFuture) }
    }

    private var focused: CourseBrief? {
        ordered.first { $0.id == selection } ?? ordered.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let focused {
                VStack(alignment: .leading, spacing: 10) {
                    card(focused)
                        .id(focused.id)
                    selector
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Tutti i corsi")
                VStack(spacing: 0) {
                    ForEach(ordered) { brief in
                        Button { open(brief.course) } label: { row(brief, last: brief.id == ordered.last?.id) }
                            .buttonStyle(.plain)
                    }
                }
                .lookCard()
            }
        }
    }

    private func card(_ brief: CourseBrief) -> some View {
        Button { open(brief.course) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    CourseMonogram(course: brief.course, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(brief.course.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(brief.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    CourseBadge(count: brief.unread)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

                CardDivider()

                CardRow(label: String(localized: "Lezione"), icon: "clock.fill", tint: brief.accent) {
                    Text(brief.whenText(locale: locale) ?? String(localized: "Nessuna in vista"))
                }
                if let room = brief.room {
                    CardDivider()
                    CardRow(String(localized: "Aula"), value: room, icon: "mappin.and.ellipse", tint: brief.accent)
                }
                if let sitting = brief.nextSitting {
                    CardDivider()
                    CardRow(label: String(localized: "Appello"), icon: "pencil.and.list.clipboard.fill",
                            tint: .orange) {
                        Text(sitting.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    /// I corsi in fila, quello scelto acceso — nello stesso posto e con la
    /// stessa spaziatura della riga di filtri della pagina.
    private var selector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ordered) { brief in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = brief.id }
                    } label: {
                        CourseMonogram(course: brief.course, size: 40)
                            .opacity(brief.id == focused?.id ? 1 : 0.4)
                            .overlay(alignment: .topTrailing) {
                                CourseBadge(count: brief.unread)
                                    .scaleEffect(0.75)
                                    .offset(x: 8, y: -6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(brief.course.name))
                    .accessibilityAddTraits(brief.id == focused?.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    private func row(_ brief: CourseBrief, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(brief.accent).frame(width: 8, height: 8)
                Text(brief.course.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                CourseBadge(count: brief.unread)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .courseRowPadding()
            if !last { CardDivider(inset: 34) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("C · Focus") {
    CoursesOptionPreview { CoursesOptionFocus(courses: CourseBrief.samples) }
}
