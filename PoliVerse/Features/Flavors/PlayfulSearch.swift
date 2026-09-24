import SwiftUI

/// The top of Cerca in Giocherelloso: the campus as a card in green with how
/// many rooms are free right now, and the student's teachers as round badges.
///
/// Reads only what is already loaded, as the rest of Cerca: the count shows
/// once Aule libere has fetched the day, and until then the card just leads
/// there. A search box that waits on the network is one nobody uses.
struct PlayfulSearchHero: View {
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var aule
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The look in use.
    @Environment(\.look) private var style

    /// The campus green: fixed rather than the look's, since it stands for the
    /// place, as the map's own colours do.
    private static let campus = Flavor.RGB(red: 0.12, green: 0.48, blue: 0.39)

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            NavigationLink(value: NewDestination.freeRooms) { campusCard }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playful-free-rooms")
            teachers
        }
    }

    // MARK: - Campus

    /// Rooms free now, when the day's timetable is loaded.
    private var freeNow: Int? {
        guard aule.loadedAt != nil else { return nil }
        let now = Date.now
        return aule.freeRooms(minimumMinutes: 30)
            .filter { $0.slots.contains { $0.contains(now) } }
            .count
    }

    /// The campus card: blocks of buildings, and the count or the way to it.
    private var campusCard: some View {
        let ink = PlayfulInk.on(Self.campus)
        return ZStack(alignment: .bottomLeading) {
            CampusBlocks(ink: ink)
                .accessibilityHidden(true)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    PlayfulKicker(text: (aule.campus ?? String(localized: "Campus")).uppercased()
                                    + String(localized: " · ADESSO"),
                                  colour: ink.opacity(0.75))
                    if let freeNow {
                        Text(freeNow == 1 ? "1 aula libera" : "\(freeNow) aule libere")
                            .font(.playful(30, relativeTo: .title))
                    } else {
                        Text("Trova un’aula libera")
                            .font(.playful(28, relativeTo: .title))
                    }
                }
                Spacer(minLength: 8)
                Text("Trova")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .foregroundStyle(Self.campus.color)
                    .background(ink, in: .capsule)
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .bottomLeading)
        .background(Self.campus.color, in: .rect(cornerRadius: 30, style: .continuous))
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .shadow(color: Self.campus.color.opacity(0.3), radius: 14, y: 8)
        .playfulLean(0, in: style)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre le aule libere")
    }

    // MARK: - Teachers

    /// The student's teachers as badges in their first course's colour.
    @ViewBuilder
    private var teachers: some View {
        let roster = Array(Teacher.roster(courses: courses.courses, sessions: career.sessions).prefix(8))
        if !roster.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PlayfulHeading("I tuoi docenti")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(roster.enumerated()), id: \.element.id) { index, teacher in
                            NavigationLink { TeacherDetailView(teacher: teacher) } label: {
                                badge(teacher, index: index)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
    }

    /// One teacher: initials on a disc, the surname under it.
    private func badge(_ teacher: Teacher, index: Int) -> some View {
        let colour = Theme.courseAccents[TodayDigest.colourIndex(for: teacher.courses.first?.name ?? teacher.name)]
        let words = teacher.name.split(separator: " ")
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return VStack(spacing: 6) {
            Text(initials)
                .font(.playful(19, relativeTo: .headline))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 58, height: 58)
                .background(colour, in: .circle)
                .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                .rotationEffect(.degrees(style.lean(index).degrees * 1.5))
            Text(words.last.map(String.init) ?? teacher.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(teacher.name))
    }
}

/// Buildings seen from above, as blocks on a green ground: a picture of a
/// campus, not a map of this one.
private struct CampusBlocks: View {
    /// The colour the blocks are drawn in.
    let ink: Color

    /// The view's content.
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            // Streets.
            var streets = Path()
            streets.move(to: CGPoint(x: 0, y: h * 0.45)); streets.addLine(to: CGPoint(x: w, y: h * 0.37))
            streets.move(to: CGPoint(x: w * 0.32, y: 0)); streets.addLine(to: CGPoint(x: w * 0.36, y: h))
            streets.move(to: CGPoint(x: w * 0.72, y: 0)); streets.addLine(to: CGPoint(x: w * 0.75, y: h))
            context.stroke(streets, with: .color(ink.opacity(0.12)), lineWidth: 12)
            // Blocks.
            let blocks: [CGRect] = [
                CGRect(x: 0.05, y: 0.08, width: 0.22, height: 0.3), CGRect(x: 0.41, y: 0.06, width: 0.27, height: 0.24),
                CGRect(x: 0.8, y: 0.05, width: 0.17, height: 0.26), CGRect(x: 0.06, y: 0.52, width: 0.2, height: 0.16),
                CGRect(x: 0.42, y: 0.46, width: 0.26, height: 0.15), CGRect(x: 0.81, y: 0.44, width: 0.16, height: 0.2),
            ]
            for block in blocks {
                let rect = CGRect(x: block.minX * w, y: block.minY * h, width: block.width * w, height: block.height * h)
                let shape = Path(roundedRect: rect, cornerRadius: 10)
                context.fill(shape, with: .color(ink.opacity(0.14)))
                context.stroke(shape, with: .color(ink.opacity(0.25)), lineWidth: 1.5)
            }
        }
    }
}
