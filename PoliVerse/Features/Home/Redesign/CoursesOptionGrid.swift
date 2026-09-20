import SwiftUI

/// **Opzione B — Griglia.** Ogni corso è una tessera, riconosciuta dal colore.
///
/// Con sei-otto corsi una lista verticale costringe a leggere i nomi per
/// trovare quello giusto; una griglia si impara a memoria per posizione e
/// monogramma, e dopo una settimana la mano ci va da sola. Ogni tessera dice
/// la cosa che cambia — quando è la prossima lezione — e porta il contatore
/// delle novità. La lezione in corso si prende la larghezza intera, così la
/// griglia ha comunque un punto di ingresso.
///
/// Le tessere sono carte del materiale scelto in Personalizza: il colore del
/// corso sta nel monogramma e in un filo di bordo, mai come velo davanti alla
/// carta — un velo sopra il materiale lo nasconde, ed è il modo in cui una
/// pagina smette di seguire il look.
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
        VStack(alignment: .leading, spacing: 24) {
            if let live {
                VStack(alignment: .leading, spacing: 10) {
                    LookHeading("A lezione adesso")
                    Button { open(live.course) } label: { wide(live) }
                        .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                LookHeading(live == nil ? "I tuoi corsi" : "Gli altri corsi")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rest) { brief in
                        Button { open(brief.course) } label: { tile(brief) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func wide(_ brief: CourseBrief) -> some View {
        CourseAccentCard(colour: brief.accent) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(brief.course.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let room = brief.room {
                        Text(room).font(.caption).opacity(0.85)
                    }
                }
                Spacer(minLength: 8)
                CourseBadge(count: brief.unread, onColour: true)
                if let end = brief.nextLectureEnd {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Adesso").font(.caption.weight(.bold))
                        Text("fino alle \(end.formatted(.dateTime.hour().minute().locale(locale)))")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ brief: CourseBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                CourseMonogram(course: brief.course, size: 34)
                Spacer(minLength: 4)
                CourseBadge(count: brief.unread)
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
                .foregroundStyle(brief.nextLecture == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(brief.accent))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .lookCard(cornerRadius: 22)
        .overlay {
            // Il filo del colore del corso, come la riga preferita di
            // ``CoursesPage``: identifica senza coprire il materiale.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(brief.accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("B · Griglia") {
    CoursesOptionPreview { CoursesOptionGrid(courses: CourseBrief.samples) }
}
