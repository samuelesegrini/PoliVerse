import SwiftUI

/// The top of Corsi in Blueprint: table 1, what is new, one row per course
/// with the count boxed at the end, most first.
struct BlueprintNewsTable: View {
    /// The courses with something new, most first.
    let news: [CourseNewsTally]

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueprintHeading(title: String(localized: "TAV. 1 — NOVITÀ"))
            VStack(spacing: 0) {
                BlueprintRule()
                ForEach(news) { item in
                    NavigationLink(value: item.course) { row(item) }
                        .buttonStyle(.plain)
                    BlueprintRule()
                }
            }
        }
    }

    /// One course: its name and what the news is, the total boxed.
    private func row(_ item: CourseNewsTally) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.course.name.uppercased())
                    .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(parts(item))
                    .font(.blueprint(11, relativeTo: .caption1))
                    .opacity(0.72)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("\(item.total)")
                .font(.blueprint(22, bold: true, relativeTo: .title2))
                .monospacedDigit()
                .frame(minWidth: 44, minHeight: 44)
                .overlay { Rectangle().strokeBorder(.white, lineWidth: 2) }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "3 FILE · 1 AVVISO · 2 DA VEDERE", leaving out what is nothing.
    private func parts(_ item: CourseNewsTally) -> String {
        var parts: [String] = []
        if item.materials > 0 { parts.append(String(localized: "\(item.materials) FILE")) }
        if item.notices > 0 {
            parts.append(item.notices == 1 ? String(localized: "1 AVVISO") : String(localized: "\(item.notices) AVVISI"))
        }
        if item.toWatch > 0 { parts.append(String(localized: "\(item.toWatch) DA VEDERE")) }
        if item.exams > 0 {
            parts.append(item.exams == 1 ? String(localized: "1 APPELLO") : String(localized: "\(item.exams) APPELLI"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Every course in Blueprint: table 2, the name and the credits in columns.
struct BlueprintCourseTable: View {
    /// The courses, favourites first.
    let courses: [Course]

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueprintHeading(title: String(localized: "TAV. 2 — CORSI"))
            VStack(spacing: 0) {
                HStack {
                    Text("INSEGNAMENTO")
                    Spacer()
                    Text("CFU")
                }
                .font(.blueprint(10, relativeTo: .caption2))
                .tracking(1.4)
                .opacity(0.72)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
                BlueprintRule()
                ForEach(courses) { course in
                    NavigationLink(value: course) {
                        HStack(spacing: 12) {
                            if course.isFavourite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .accessibilityLabel("Preferito")
                            }
                            Text(course.name.uppercased())
                                .font(.blueprint(14, relativeTo: .subheadline))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text("\(course.cfu)")
                                .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                                .monospacedDigit()
                                .accessibilityLabel(Text("\(course.cfu) CFU"))
                        }
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    BlueprintRule()
                }
            }
        }
    }
}
