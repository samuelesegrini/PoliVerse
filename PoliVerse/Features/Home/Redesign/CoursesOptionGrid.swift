import SwiftUI

/// **Opzione B — Griglia.** Ogni corso è una tessera del suo colore.
///
/// Con sei-otto corsi una lista verticale costringe a leggere i nomi per
/// trovare quello giusto; una griglia si impara a memoria per posizione e
/// colore, e dopo una settimana la mano ci va da sola. Ogni tessera dice la
/// cosa che cambia — quando è la prossima lezione — e porta il pallino delle
/// novità. La lezione in corso si prende due colonne, così la griglia ha
/// comunque un punto di ingresso.
struct CoursesOptionGrid: View {
    let courses: [CourseBrief]
    var open: (Course) -> Void = { _ in }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Con i corpi grandi la griglia diventa una colonna sola: due tessere
    /// affiancate a quel punto troncano il nome, che è l'unica cosa che conta.
    private var columns: [GridItem] {
        typeSize >= .accessibility1
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var live: CourseBrief? { courses.first(where: \.isOngoing) }
    private var rest: [CourseBrief] { courses.filter { $0.id != live?.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let live {
                Button { open(live.course) } label: { wide(live) }
                    .buttonStyle(.plain)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(rest) { brief in
                    Button { open(brief.course) } label: { tile(brief) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func wide(_ brief: CourseBrief) -> some View {
        HStack(spacing: 14) {
            CourseGlyph(course: brief.course, size: 46, filled: false)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 3, y: -3)
                        .opacity(brief.unread > 0 ? 1 : 0)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("In corso adesso")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(brief.accent)
                Text(brief.course.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let end = brief.nextLectureEnd {
                    Text("fino alle \(end.formatted(.dateTime.hour().minute().locale(locale)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let room = brief.room {
                Text(room)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(brief.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(brief.accent.opacity(0.14), in: .capsule)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(brief.accent.opacity(0.5), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ brief: CourseBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                CourseGlyph(course: brief.course, size: 34, filled: false)
                Spacer(minLength: 4)
                UnreadDot(count: brief.unread)
            }
            Spacer(minLength: 10)
            Text(brief.course.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(brief.whenText(locale: locale) ?? brief.subtitle)
                .font(.caption)
                .foregroundStyle(brief.nextLecture == nil ? .secondary : brief.accent)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background {
            // Una velatura del colore del corso sul materiale scelto: la
            // tessera resta della "carta" del look, ma si riconosce da lontano.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(brief.accent.opacity(0.10))
        }
        .lookCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

#Preview("B · Griglia") {
    ScrollView {
        CoursesOptionGrid(courses: CourseBrief.samples)
            .padding(20)
    }
    .previewEnvironment()
}
