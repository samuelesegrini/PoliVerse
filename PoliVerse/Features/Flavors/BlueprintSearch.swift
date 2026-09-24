import SwiftUI

/// The top of Cerca in Blueprint: the campus as a plan drawn in outline, with
/// how many rooms are free now once Aule libere has loaded, and the student's
/// teachers as the drawing's legend.
struct BlueprintSearchHero: View {
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var aule
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The look in use.
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink(value: NewDestination.freeRooms) { plan }
                .buttonStyle(.plain)
                .accessibilityIdentifier("blueprint-free-rooms")
            legend
        }
    }

    /// Rooms free now, when the day's timetable is loaded.
    private var freeNow: Int? {
        guard aule.loadedAt != nil else { return nil }
        let now = Date.now
        return aule.freeRooms(minimumMinutes: 30).filter { $0.slots.contains { $0.contains(now) } }.count
    }

    /// The campus in outline, the count under it.
    private var plan: some View {
        let palette = BlueprintPalette(style)
        let campus = (aule.campus ?? String(localized: "Campus")).uppercased()
        return BlueprintBox(label: String(localized: "PIANTA — \(campus)")) {
            VStack(alignment: .leading, spacing: 12) {
                OutlineBlocks()
                    .frame(height: 110)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline) {
                    if let freeNow {
                        Text(freeNow == 1 ? String(localized: "1 AULA LIBERA") : String(localized: "\(freeNow) AULE LIBERE"))
                            .font(.blueprint(20, bold: true, relativeTo: .title3))
                            .foregroundStyle(palette.mark)
                    } else {
                        Text("TROVA UN’AULA LIBERA")
                            .font(.blueprint(18, bold: true, relativeTo: .title3))
                    }
                    Spacer(minLength: 8)
                    Text("APRI →")
                        .font(.blueprint(12, bold: true, relativeTo: .caption1))
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre le aule libere")
    }

    /// The teachers as the drawing's legend: initials in a square, the name beside.
    @ViewBuilder
    private var legend: some View {
        let roster = Array(Teacher.roster(courses: courses.courses, sessions: career.sessions).prefix(6))
        if !roster.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                BlueprintHeading(title: String(localized: "LEGENDA — DOCENTI"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    ForEach(roster) { teacher in
                        NavigationLink { TeacherDetailView(teacher: teacher) } label: {
                            HStack(spacing: 10) {
                                Text(initials(teacher.name))
                                    .font(.blueprint(13, bold: true, relativeTo: .subheadline))
                                    .frame(width: 36, height: 36)
                                    .overlay { Rectangle().strokeBorder(.white, lineWidth: 1.5) }
                                Text(teacher.name.split(separator: " ").last.map(String.init)?.uppercased() ?? teacher.name)
                                    .font(.blueprint(12, relativeTo: .caption1))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(teacher.name))
                    }
                }
            }
        }
    }

    /// The first letters of the first two words.
    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// Buildings from above, drawn only in outline, with hatching on one: a
/// picture of a campus, not a map of this one.
private struct OutlineBlocks: View {
    /// The view's content.
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let blocks: [CGRect] = [
                CGRect(x: 0.0, y: 0.0, width: 0.24, height: 0.55), CGRect(x: 0.3, y: 0.0, width: 0.34, height: 0.4),
                CGRect(x: 0.7, y: 0.0, width: 0.3, height: 0.5), CGRect(x: 0.0, y: 0.68, width: 0.3, height: 0.32),
                CGRect(x: 0.36, y: 0.52, width: 0.28, height: 0.48), CGRect(x: 0.72, y: 0.64, width: 0.28, height: 0.36),
            ]
            for (index, block) in blocks.enumerated() {
                let rect = CGRect(x: block.minX * w, y: block.minY * h, width: block.width * w, height: block.height * h)
                context.stroke(Path(rect), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                if index == 4 {
                    // One building hatched, as a drawing marks a section.
                    var hatch = Path()
                    var x = rect.minX - rect.height
                    while x < rect.maxX {
                        hatch.move(to: CGPoint(x: x, y: rect.maxY)); hatch.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                        x += 8
                    }
                    context.drawLayer { layer in
                        layer.clip(to: Path(rect))
                        layer.stroke(hatch, with: .color(.white.opacity(0.35)), lineWidth: 1)
                    }
                }
            }
        }
    }
}
