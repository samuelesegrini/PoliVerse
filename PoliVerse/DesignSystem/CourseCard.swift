import SwiftUI

/// The course tile on Home.
///
/// A tappable card that answers "what is next for this course" at a glance:
/// the next lecture, the next sitting, and what is new — with secondary
/// actions in a menu instead of a row of buttons competing with the title.
struct CourseCard: View {
    let course: Course
    let onOpen: () -> Void
    let onFavourite: () -> Void
    let onMaterials: () -> Void
    var onHide: () -> Void = {}

    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.locale) private var locale

    private var accent: Color { Theme.accent(for: course) }

    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 46

    /// Matched by name, as on the course page: the agenda carries no code.
    private var nextLecture: AgendaEvent? {
        let target = course.name.lowercased()
        return agenda.events
            .lazy
            .filter { $0.kind == .lecture && $0.end > .now }
            .filter { let title = $0.title.lowercased(); return title.contains(target) || target.contains(title) }
            .min { $0.start < $1.start }
    }

    private var nextSitting: ExamSession? {
        career.upcoming.first { $0.isOf(courseCode: course.id, courseName: course.name) }
    }

    private var badges: CourseHubBadges {
        CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
    }

    /// "AR" for "Architetture dei Calcolatori": skips the short joining words.
    private var monogram: String {
        let skip: Set<String> = ["di", "dei", "del", "della", "delle", "e", "ed", "per", "a", "and", "of", "the", "in"]
        let letters = course.name
            .split(whereSeparator: { !$0.isLetter })
            .filter { !skip.contains($0.lowercased()) }
            .prefix(2)
            .compactMap(\.first)
        return String(letters).uppercased()
    }

    var body: some View {
        let lecture = nextLecture
        let sitting = nextSitting
        let badges = badges

        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(monogram)
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: monogramSize, height: monogramSize)
                        .background(accent.gradient, in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(course.name)
                            .font(.headline)
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    menu
                }

                if lecture != nil || sitting != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let lecture {
                            infoLine(icon: "clock.fill", tint: accent,
                                     title: lectureText(lecture),
                                     trailing: lecture.roomAcronym ?? lecture.room)
                        }
                        if let sitting {
                            infoLine(icon: "pencil.and.list.clipboard", tint: sitting.status == .open ? .orange : accent,
                                     title: sittingText(sitting),
                                     trailing: sitting.status.label)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08), in: .rect(cornerRadius: 16))
                }

                if badges.announcements + badges.materials + badges.exams > 0 {
                    HStack(spacing: 6) {
                        badge(badges.announcements, "megaphone.fill", "avvisi")
                        badge(badges.materials, "folder.fill", "materiali")
                        badge(badges.exams, "bell.badge.fill", "esami")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookCard(cornerRadius: Theme.cardCorner)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .strokeBorder(accent.opacity(course.isFavourite ? 0.45 : 0), lineWidth: 1.5)
            }
            .contentShape(.rect(cornerRadius: Theme.cardCorner))
        }
        .buttonStyle(CardPressStyle())
        .contextMenu { menuItems }
        .accessibilityHint("Apre il corso")
    }

    private var subtitle: String {
        var parts: [String] = []
        if !course.teacher.isEmpty, course.teacher != "—" { parts.append(course.teacher) }
        if course.cfu > 0 { parts.append("\(course.cfu) CFU") }
        if course.semester != "—" { parts.append(String(localized: "Sem. \(course.semester)")) }
        return parts.joined(separator: " · ")
    }

    private var menu: some View {
        Menu { menuItems } label: {
            Image(systemName: course.isFavourite ? "star.fill" : "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(course.isFavourite ? .yellow : .secondary)
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .accessibilityLabel("Altre azioni")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(course.isFavourite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
               systemImage: course.isFavourite ? "star.slash" : "star",
               action: onFavourite)
        Button("Apri materiali", systemImage: "folder", action: onMaterials)
        Divider()
        // Mirrors WeBeep's own "Rimuovi dalla vista": the course stays
        // enrolled, it just stops crowding the list.
        Button("Rimuovi dalla vista", systemImage: "eye.slash", action: onHide)
    }

    private func infoLine(icon: String, tint: Color, title: String, trailing: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func lectureText(_ lecture: AgendaEvent) -> String {
        let time = lecture.start.formatted(.dateTime.hour().minute().locale(locale))
        if lecture.start <= .now { return String(localized: "Lezione in corso") }
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(lecture.start) { return String(localized: "Oggi alle \(time)") }
        if calendar.isDateInTomorrow(lecture.start) { return String(localized: "Domani alle \(time)") }
        return lecture.start.formatted(.dateTime.weekday(.wide).hour().minute().locale(locale)).capitalized
    }

    private func sittingText(_ sitting: ExamSession) -> String {
        guard let date = sitting.date else { return String(localized: "Appello da definire") }
        return String(localized: "Appello \(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))")
    }

    @ViewBuilder
    private func badge(_ count: Int, _ icon: String, _ label: String) -> some View {
        if count > 0 {
            Label("\(count)", systemImage: icon)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12), in: .capsule)
                .foregroundStyle(.red)
                .accessibilityLabel(Text("\(count) novità \(label)"))
        }
    }
}

/// A slight shrink on press, so a whole-card tap feels like a tap.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CourseCard(course: Course.samples[0], onOpen: {}, onFavourite: {}, onMaterials: {})
        .padding()
        .previewEnvironment()
}
