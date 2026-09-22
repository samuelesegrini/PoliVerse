import SwiftUI

/// Everything the app has noticed about the student's exams, newest first.
///
/// The feed replaces the habit of opening each sitting to see whether anything
/// moved. It says only what official data said, and where it said it.
struct ExamUpdatesView: View {
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    @State private var selectedExam: ExamSession?
    /// When the feed was last seen before this visit: what is newer keeps its
    /// dot for as long as the screen is open.
    @State private var seenBefore: Date?
    @State private var hasMarked = false
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The bell, and how many are still to read.
    private var hero: some View {
        let ramp = FlavorRamp(style: style, scheme: scheme)
        let unread = FeedItem.items(from: feed.updates).filter { $0.isUnread(since: seenBefore) }.count
        return CoursePageHero(
            tiles: [HeroTile(id: "bell", symbol: "bell.badge", colour: ramp.colour(at: 0.3))],
            placeholder: HeroTile(id: "empty", symbol: "bell.badge", colour: ramp.neutral),
            title: unread == 0 ? Text("Tutto letto") : Text(unread == 1 ? "1 novità da leggere" : "\(unread) novità da leggere"),
            summary: Text("Dai Servizi Online e da WeBeep"),
            badge: unread > 0 ? HeroBadge(symbol: "bell.fill", tint: style.accent(scheme)) : nil,
            mode: ramp.mode)
    }

    /// The feed grouped by the day each update was noticed, newest day and newest update first.
    private var days: [(Date, [FeedItem])] {
        let calendar = PoliMiDate.romeCalendar
        return Dictionary(grouping: FeedItem.items(from: feed.updates)) {
            calendar.startOfDay(for: $0.update.detectedAt)
        }
        .sorted { $0.key > $1.key }
        .map { ($0.key, $0.value.sorted { $0.update.detectedAt > $1.update.detectedAt }) }
    }

    /// "Oggi", "Ieri", or the day in words.
    private func dayTitle(_ day: Date) -> String {
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(day) { return String(localized: "Oggi") }
        if calendar.isDateInYesterday(day) { return String(localized: "Ieri") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized
    }

    /// The view's content.
    var body: some View {
        ScrollView {
            if feed.updates.isEmpty {
                ContentUnavailableView(
                    "Nessuna novità",
                    systemImage: "bell.badge",
                    description: Text("Quando cambia qualcosa nei tuoi appelli — un'aula, un esito, un appello spostato — lo trovi qui."))
                    .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 26) {
                    hero
                    ForEach(days, id: \.0) { day, items in
                        // One card a day, under Oggi's heading.
                        VStack(alignment: .leading, spacing: 10) {
                            LookHeading(verbatim: dayTitle(day))
                            VStack(spacing: 0) {
                                ForEach(items) { item in
                                    let sitting = career.sitting(for: item.update)
                                    Button { selectedExam = sitting } label: {
                                        // Under a day heading, the time says more
                                        // than "3 days ago".
                                        ExamUpdateRow(item: item, showsClockTime: true,
                                                      isUnread: item.isUnread(since: seenBefore), card: false)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(sitting == nil)
                                    if item.id != items.last?.id { Divider().padding(.leading, 52) }
                                }
                            }
                            .lookCard()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            // Honest about what this can and cannot see, and how to quiet it.
            Text("Le novità arrivano dai Servizi Online quando l'app si aggiorna: aprendola, o in background quando iOS lo consente. Le email dei docenti non sono incluse. Tieni premuta una novità per silenziarne il corso.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .navigationTitle("Novità esami")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await career.load(force: true) }
        .sheet(item: $selectedExam) { ExamDetailView(exam: $0) }
        .onAppear {
            // Once per visit: coming back to the tab must not clear the dots
            // of a screen still open.
            if !hasMarked {
                seenBefore = feed.seenAt
                hasMarked = true
            }
            feed.markSeen()
        }
    }
}

/// One update: what changed, for which course, and when it was seen.
struct ExamUpdateRow: View {
    /// The update this row is about, with the course it belongs to.
    let item: FeedItem
    /// Shows the time of day rather than how long ago, for the rows already grouped under a day.
    var showsClockTime = false
    /// Marks the row as not yet seen.
    var isUnread = false
    /// On a card of its own; off where the rows share one card.
    var card = true
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications

    /// The update itself.
    private var update: ExamUpdate { item.update }

    /// The view's content.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: update.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(update.kind.tint)
                .frame(width: 28, height: 28)
                .background(update.kind.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(update.title)
                    .font(.subheadline.weight(.semibold))
                Text([update.courseName, item.detail, item.note].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // §17: every value says where it came from and how sure it is.
                Text([update.sourceLabel, update.confidenceNote].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(showsClockTime
                     ? update.detectedAt.formatted(.dateTime.hour().minute().locale(locale))
                     : update.detectedAt.formatted(.relative(presentation: .named).locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                if isUnread {
                    Circle().fill(Theme.brand).frame(width: 8, height: 8)
                        .accessibilityLabel("Non letta")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(UpdateRowSurface(card: card))
        .opacity(item.isSuperseded ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .contextMenu { muteButton }
    }

    /// §13: silence a course from the news itself, where the noise is seen.
    @ViewBuilder
    private var muteButton: some View {
        let code = update.courseCode, name = update.courseName
        if notifications.preferences.isMuted(code: code, name: name) {
            Button {
                notifications.preferences.setMuted(false, code: code, name: name)
            } label: {
                Label("Riattiva le notifiche di \(update.courseName)", systemImage: "bell")
            }
        } else {
            Button {
                notifications.preferences.setMuted(true, code: code, name: name)
            } label: {
                Label("Silenzia \(update.courseName)", systemImage: "bell.slash")
            }
        }
    }
}

/// A sitting's timeline, for the detail sheet.
struct ExamTimelineSection: View {
    /// The sitting whose history is shown.
    let exam: ExamSession
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// Everything that has happened to the sitting, and what is still to come, in order.
    private var entries: [ExamTimelineEntry] {
        ExamTimeline.entries(for: exam, sittings: career.sessions, updates: feed.updates, now: .now)
    }

    /// The view's content.
    var body: some View {
        let entries = entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Cronologia")

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        line(entry, isLast: index == entries.count - 1)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lookCard()
            }
        }
    }

    /// One entry of the timeline: its dot, its rail, and what happened.
    ///
    /// - Parameters:
    ///   - entry: The entry to draw.
    ///   - isLast: True for the last entry, which draws no rail below it.
    /// - Returns: The line.
    private func line(_ entry: ExamTimelineEntry, isLast: Bool) -> some View {
        let tint = entry.update?.kind.tint ?? .secondary
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .background(Circle().fill(entry.isFuture ? Color.clear : tint))
                    .frame(width: 12, height: 12)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(entry.isFuture ? .secondary : .primary)
                if let detail = entry.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                // Where it came from, and whether it was read or inferred.
                Text(entry.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The colour each kind of update is shown in.
extension ExamUpdate.Kind {
    /// The kind's colour: green for a result, orange for a change, red for something withdrawn, and the career's own colours for the states they belong to.
    var tint: Color {
        switch self {
        case .gradePublished, .gradeRecorded: .green
        case .refusalOpened: CareerState.refusable.tint
        case .roomChanged, .dateChanged: .orange
        case .withdrawn, .unenrolled: .red
        case .roomPublished, .enrolled, .correctionsAvailable: Theme.brand
        case .enrolmentOpened: CareerState.enrolmentOpen.tint
        case .discovered: .indigo
        case .resultsPosted: .green
        case .solutionsPosted, .examNoticePosted: .teal
        case .materialAdded: .secondary
        case .announcementPosted: Theme.brand
        case .assignmentAdded: .indigo
        case .deadlineChanged: .orange
        }
    }
}

// MARK: - Previews

#Preview("Novità esami") {
    ExamUpdatesView().previewInNavigation()
}

#Preview("Cronologia appello") {
    ScrollView {
        ExamTimelineSection(exam: ExamSession.samples()[0]).padding()
    }
    .previewEnvironment()
}

/// A row of the feed is a card on its own page and a plain row inside a
/// section that is already one. Either way the card is the look's material,
/// not a fixed system grey.
private struct UpdateRowSurface: ViewModifier {
    /// True when the row draws its own card.
    let card: Bool

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        if card {
            content.lookCard(cornerRadius: Theme.cardCorner)
        } else {
            content
        }
    }
}
