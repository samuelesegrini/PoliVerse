import SwiftUI

/// **Opzione C — Focus.** Una carta grande alla volta, il resto in una riga.
///
/// Prende sul serio l'idea che di solito un corso solo è quello "attivo": la
/// carta in evidenza lo racconta per intero — lezione, aula, appello, novità —
/// e le altre scorrono orizzontalmente accanto. Sotto, un elenco minimo per
/// arrivare comunque a tutto. È la pagina che fa più bella figura con pochi
/// corsi e che regge peggio la crescita: a dodici corsi la riga orizzontale
/// diventa un nastro da scorrere alla cieca.
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
        VStack(alignment: .leading, spacing: 18) {
            if let focused {
                card(focused)
                    .id(focused.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            }

            // Il selettore: i corsi in fila, quello scelto acceso.
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ordered) { brief in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { selection = brief.id }
                        } label: {
                            chip(brief, chosen: brief.id == focused?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)

            LookHeading("Tutti i corsi")
            VStack(spacing: 0) {
                ForEach(ordered) { brief in
                    Button { open(brief.course) } label: { row(brief, last: brief.id == ordered.last?.id) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .lookCard()
        }
    }

    private func card(_ brief: CourseBrief) -> some View {
        Button { open(brief.course) } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    CourseGlyph(course: brief.course, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(brief.course.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(brief.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    fact(icon: "clock.fill", tint: brief.accent,
                         text: brief.whenText(locale: locale) ?? String(localized: "Nessuna lezione in vista"),
                         trailing: brief.room)
                    if let sitting = brief.nextSitting {
                        fact(icon: "pencil.and.list.clipboard.fill", tint: .orange,
                             text: String(localized: "Appello \(sitting.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"),
                             trailing: nil)
                    }
                    if brief.unread > 0 {
                        fact(icon: "sparkles", tint: .red,
                             text: String(localized: "\(brief.unread) novità da vedere"), trailing: nil)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(brief.accent.opacity(0.09), in: .rect(cornerRadius: 18, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    private func fact(icon: String, tint: Color, text: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ brief: CourseBrief, chosen: Bool) -> some View {
        VStack(spacing: 6) {
            CourseGlyph(course: brief.course, size: 40, circular: true, filled: chosen)
                .overlay(alignment: .topTrailing) {
                    UnreadDot(count: brief.unread).scaleEffect(0.8).offset(x: 6, y: -4)
                }
            Text(brief.course.monogram)
                .font(.caption2.weight(chosen ? .bold : .regular))
                .foregroundStyle(chosen ? .primary : .secondary)
        }
        .frame(width: 56)
        .accessibilityLabel(Text(brief.course.name))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func row(_ brief: CourseBrief, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(brief.accent).frame(width: 8, height: 8)
                Text(brief.course.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                UnreadDot(count: brief.unread)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 11)
            if !last { Divider().padding(.leading, 18) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("C · Focus") {
    ScrollView {
        CoursesOptionFocus(courses: CourseBrief.samples)
            .padding(20)
    }
    .previewEnvironment()
}
