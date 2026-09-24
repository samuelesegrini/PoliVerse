import SwiftUI

/// What is new in one course, as the special Flavors' Corsi count it.
struct CourseNewsTally: Identifiable {
    /// The course.
    let course: Course
    /// Its colour on the course's own pages.
    let colour: Flavor.RGB
    /// Unread notices.
    let notices: Int
    /// New materials.
    let materials: Int
    /// Exam news.
    let exams: Int
    /// Recorded lessons not yet watched.
    let toWatch: Int

    /// The course's identity.
    var id: String { course.id }

    /// Everything new, added up.
    var total: Int { notices + materials + exams + toWatch }
}

/// The top of Corsi in Giocherelloso: one tall card per course with news, in
/// the course's colour, the count huge and what it is made of under it.
/// Ordered by how much is new, not by the clock: what is on now is Oggi's,
/// and the lesson bar above the tabs.
struct PlayfulNewsRail: View {
    /// The courses with something new, most first.
    let news: [CourseNewsTally]

    /// The look in use.
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(news.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.course) {
                        card(item, large: index == 0)
                    }
                    .buttonStyle(.plain)
                    .playfulLean(index, in: style)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    /// One course's card: the count, the name, and the kinds of news.
    private func card(_ item: CourseNewsTally, large: Bool) -> some View {
        let ink = PlayfulInk.on(item.colour)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(item.total)")
                    .font(.playful(large ? 72 : 56, relativeTo: .largeTitle))
                    .monospacedDigit()
                PlayfulKicker(text: String(localized: "NOVITÀ"), colour: ink.opacity(0.75))
            }
            Spacer(minLength: 8)
            Text(item.course.name)
                .font(.playful(large ? 23 : 20, relativeTo: .title2))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if large {
                VStack(alignment: .leading, spacing: 6) {
                    kind(item.materials, one: "1 file nuovo", many: "\(item.materials) file nuovi", symbol: "doc")
                    kind(item.notices, one: "1 avviso", many: "\(item.notices) avvisi", symbol: "megaphone")
                    kind(item.toWatch, one: "1 lezione da vedere", many: "\(item.toWatch) lezioni da vedere",
                         symbol: "play.rectangle")
                    kind(item.exams, one: "1 novità sugli appelli", many: "\(item.exams) novità sugli appelli",
                         symbol: "graduationcap")
                }
                .font(.footnote.weight(.medium))
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(width: large ? 250 : 190, height: 290, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(item.colour.color)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: SubjectSymbol.symbol(for: item.course.name))
                        .font(.system(size: 120))
                        .foregroundStyle(ink.opacity(0.12))
                        .offset(x: 30, y: -24)
                        .accessibilityHidden(true)
                }
                .clipShape(.rect(cornerRadius: 30, style: .continuous))
                .shadow(color: item.colour.color.opacity(0.35), radius: 14, y: 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// A line for one kind of news, or nothing when there is none of it.
    @ViewBuilder
    private func kind(_ count: Int, one: LocalizedStringKey, many: LocalizedStringKey, symbol: String) -> some View {
        if count > 0 {
            Label(count == 1 ? one : many, systemImage: symbol)
                .lineLimit(1)
        }
    }
}

/// Every course as a book on a shelf: a spine in its colour, as tall as its
/// credits, the name running up it.
struct PlayfulShelf: View {
    /// The courses, favourites first.
    let courses: [(course: Course, colour: Flavor.RGB)]

    /// The look in use.
    @Environment(\.look) private var style
    /// The reader's text size, which lays the spines flat when names would not fit up them.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The view's content.
    var body: some View {
        if typeSize.isAccessibilitySize {
            // Names up a spine are unreadable this large: the books lie flat.
            VStack(spacing: 8) {
                ForEach(courses, id: \.course.id) { entry in
                    NavigationLink(value: entry.course) { flat(entry.course, colour: entry.colour) }
                        .buttonStyle(.plain)
                }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(courses.enumerated()), id: \.element.course.id) { index, entry in
                        NavigationLink(value: entry.course) { spine(entry.course, colour: entry.colour) }
                            .buttonStyle(.plain)
                            // Only the last book leans, against nothing.
                            .rotationEffect(index == courses.count - 1 ? .degrees(style.lean(3).degrees * 2) : .zero,
                                            anchor: .bottomLeading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.primary).frame(height: 6)
                    .padding(.horizontal, -20)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A course standing up: its name up the spine, its credits at the foot.
    private func spine(_ course: Course, colour: Flavor.RGB) -> some View {
        let height = min(max(120 + CGFloat(course.cfu) * 6, 130), 200)
        let ink = PlayfulInk.on(colour)
        return VStack(spacing: 6) {
            Text(course.name)
                .font(.playful(15, relativeTo: .subheadline))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: height - 40)
                .clipped()
            Text("\(course.cfu)")
                .font(.playful(11, relativeTo: .caption2))
                .opacity(0.85)
        }
        .foregroundStyle(ink)
        .frame(width: 56, height: height)
        .background(colour.color, in: UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 2,
                                                              bottomTrailingRadius: 2, topTrailingRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(course.name))
        .accessibilityValue(Text("\(course.cfu) CFU"))
    }

    /// A course lying flat, for the largest text sizes.
    private func flat(_ course: Course, colour: Flavor.RGB) -> some View {
        HStack {
            Text(course.name).font(.playful(17, relativeTo: .body))
            Spacer(minLength: 8)
            Text("\(course.cfu) CFU").font(.caption.weight(.semibold))
        }
        .foregroundStyle(PlayfulInk.on(colour))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colour.color, in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// Black or white, whichever reads on a colour.
enum PlayfulInk {
    /// The ink for a fill.
    ///
    /// - Parameter colour: The fill.
    /// - Returns: Black or white.
    static func on(_ colour: Flavor.RGB) -> Color {
        Flavor.contrast(.white, colour) >= Flavor.contrast(.black, colour) ? .white : .black
    }
}
