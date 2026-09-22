import SwiftUI

/// A course's announcements, or its discussion forums, from WeBeep.
///
/// Reached from the course page's hub. When the page has more than one
/// discussion forum, each is listed; a single forum opens straight away.
struct CourseForumsView: View {
    /// The course whose forums these are.
    let course: Course
    /// Whether to show the announcements forum or the discussion forums.
    let kind: CourseForum.Kind

    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The course page's forums, or `nil` before they have been read — which is not the same
    /// as a page with none.
    @Environment(WeBeepModel.self) private var weBeep
    @State private var forums: [CourseForum]?
    @State private var loaded = false
    @State private var showingLogin = false

    /// The screen's name, which depends on which kind of forum is shown.
    private var title: String {
        kind == .announcements ? String(localized: "Avvisi") : String(localized: "Forum")
    }

    /// The course's own accent.
    private var tint: Color { Theme.accent(for: course) }

    /// The forums of the kind being shown.
    private var matching: [CourseForum] { (forums ?? []).filter { $0.kind == kind } }

    /// The view's content.
    var body: some View {
        Group {
            if !session.useMockData && !weBeep.isAuthenticated {
                ContentUnavailableView {
                    Label("Collega WeBeep", systemImage: "link")
                } description: {
                    Text("Avvisi e forum arrivano da WeBeep, che usa un accesso separato.")
                } actions: {
                    Button("Accedi a WeBeep") { showingLogin = true }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                }
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if forums == nil {
                ContentUnavailableView("WeBeep non risponde", systemImage: "wifi.exclamationmark",
                                       description: Text("Riprova tra poco."))
            } else if matching.count == 1, let forum = matching.first {
                DiscussionsList(forum: forum, course: course, kind: kind, tint: tint)
            } else if matching.isEmpty {
                ContentUnavailableView(
                    kind == .announcements ? "Nessun forum avvisi" : "Nessun forum",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("La pagina WeBeep di questo corso non ne ha."))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(matching.enumerated()), id: \.element.id) { index, forum in
                            if index > 0 { CardDivider(inset: 60) }
                            NavigationLink {
                                DiscussionsList(forum: forum, course: course, kind: kind, tint: tint)
                                    .navigationTitle(forum.name)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .foregroundStyle(tint)
                                        .frame(width: 34, height: 34)
                                        .background(tint.opacity(0.13), in: .rect(cornerRadius: 10))
                                    Text(forum.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .lookCard()
                    .padding(.horizontal, 20).padding(.vertical)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weBeep.isAuthenticated) { await load() }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet { await load() }
        }
    }

    /// Reads the course page's forums, unless WeBeep is not connected.
    private func load() async {
        guard session.useMockData || weBeep.isAuthenticated else { return }
        forums = await weBeep.forums(for: course)
        loaded = true
    }
}

/// The discussions in one forum, newest activity first as Moodle orders them.
private struct DiscussionsList: View {
    /// The forum being listed.
    let forum: CourseForum
    /// The course it belongs to, which supplies the accent ramp.
    let course: Course
    /// Which kind of forum it is, which decides the heading and the symbol.
    let kind: CourseForum.Kind
    /// The course's own accent.
    let tint: Color

    /// The look in use, which the page's materials and typeface come from.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The forum as a pile: its own symbol in front, then what fills it.
    private func hero(_ discussions: [MoodleDiscussion]) -> some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        let front = kind == .announcements ? "megaphone" : "bubble.left.and.bubble.right"
        let symbols = [front, "pin", "person.2", "paperclip", "bell"]
        let latest = discussions.compactMap(\.created).max().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let count = Text(discussions.count == 1 ? "1 discussione" : "\(discussions.count) discussioni")
        return CoursePageHero(
            tiles: zip(symbols, ramp.colours(symbols.count)).map { HeroTile(id: $0, symbol: $0, colour: $1) },
            placeholder: HeroTile(id: "empty", symbol: front, colour: ramp.main),
            title: Text(verbatim: forum.name),
            summary: latest.map { Text("\(count) · l'ultima \($0.formatted(.relative(presentation: .named).locale(locale)))") } ?? count,
            mode: ramp.mode)
    }

    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    @State private var discussions: [MoodleDiscussion]?
    @State private var failed = false

    /// The view's content.
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let discussions {
                    if discussions.isEmpty {
                        ContentUnavailableView("Ancora nessun messaggio", systemImage: "bubble.left")
                            .padding(.top, 40)
                    } else {
                        hero(discussions)
                            .padding(.bottom, 14)
                        VStack(spacing: 0) {
                            ForEach(discussions, id: \.id) { discussion in
                                NavigationLink {
                                    DiscussionView(discussion: discussion, tint: tint)
                                } label: {
                                    row(discussion, last: discussion.id == discussions.last?.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .lookCard()
                    }
                } else if failed {
                    ContentUnavailableView("Forum non disponibile", systemImage: "wifi.exclamationmark",
                                           description: Text("Non riesco a leggere questo forum."))
                        .padding(.top, 40)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 20).padding(.vertical)
        }
        .refreshable { await load() }
        .task { if discussions == nil { await load() } }
    }

    /// A discussion as a row of the forum's card: who, what, and the start
    /// of what they said; a pinned one says so with the course's colour.
    private func row(_ discussion: MoodleDiscussion, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                InitialsAvatar(name: discussion.userfullname ?? "?", tint: tint, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if discussion.pinned == true {
                            Label("In evidenza", systemImage: "pin.fill")
                                .labelStyle(.iconOnly)
                                .font(.caption)
                                .foregroundStyle(tint)
                        }
                        Text(discussion.subject ?? discussion.name ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let created = discussion.created {
                            Text(Date(timeIntervalSince1970: TimeInterval(created))
                                .formatted(.relative(presentation: .named).locale(locale)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Text(discussion.userfullname ?? "")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(HTMLText.plain(discussion.message ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 12)
            if !last { Divider().padding(.leading, 50) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// Reads the forum's discussions. A failure is only reported when there is nothing already
    /// on screen.
    private func load() async {
        do {
            discussions = try await weBeep.discussions(in: forum)
            failed = false
        } catch {
            failed = discussions == nil
        }
    }
}

/// One thread: the opening post and its replies, oldest first.
private struct DiscussionView: View {
    /// The thread being shown.
    let discussion: MoodleDiscussion
    /// The course's own accent.
    let tint: Color

    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The thread's posts, oldest first, or `nil` before they have been read.
    @Environment(\.locale) private var locale
    @State private var posts: [MoodlePosts.Post]?
    /// The one-line summary of a long thread, written on the device.
    @State private var summary = NoticeSummary()

    /// The thread as plain text: the opening post and every reply that has
    /// arrived, which is what a summary of "this notice" means.
    private var plainText: String {
        (posts ?? fallback)
            .map { HTMLText.plain($0.message ?? "") }
            .joined(separator: "\n\n")
    }

    /// The view's content.
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(discussion.subject ?? discussion.name ?? "")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                summaryCard

                ForEach(posts ?? fallback) { post in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            InitialsAvatar(name: post.author?.fullname ?? "?", tint: tint, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(post.author?.fullname ?? "").font(.subheadline.weight(.semibold))
                                if let created = post.created {
                                    Text(created.formatted(.dateTime.day().month().hour().minute().locale(locale)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if post.isReply, let subject = post.subject {
                            Text(subject).font(.caption).foregroundStyle(.secondary)
                        }
                        RichText(html: post.message, plain: nil)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lookCard()
                    .padding(.leading, post.isReply ? 20 : 0)
                    .overlay(alignment: .leading) {
                        if post.isReply {
                            RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.4)).frame(width: 3).padding(.leading, 6)
                        }
                    }
                }
                if posts == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20).padding(.vertical)
        }
        .navigationTitle(discussion.subject ?? discussion.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { posts = try? await weBeep.posts(in: discussion) }
    }

    /// The summary, offered only for a long thread on a device that can write
    /// one, and only when the student asks.
    ///
    /// Never automatic: a summary that appears by itself is a claim the app
    /// makes about the lecturer's words before anyone has asked for one.
    @ViewBuilder
    private var summaryCard: some View {
        if NoticeSummary.isAvailable, NoticeSummary.isWorthSummarising(plainText) {
            VStack(alignment: .leading, spacing: 8) {
                switch summary.state {
                case .idle:
                    Button {
                        Task { await summary.summarise(plainText) }
                    } label: {
                        Label("Riassumi", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                case .writing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Sto riassumendo…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .ready(let text):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("In breve", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                        Text(text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        // The avviso underneath is what counts: say so, rather
                        // than letting a generated sentence stand as the notice.
                        Text("Riassunto sul dispositivo. L'avviso originale è qui sotto.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .unavailable:
                    // Nothing: the notice reads as it did before.
                    EmptyView()
                }
            }
            .padding(summary.state == .idle ? 0 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SummaryCardBackground(showing: summary.state != .idle))
        }
    }

    /// The opening post, which the discussion list already has, while the
    /// replies load.
    private var fallback: [MoodlePosts.Post] {
        [MoodlePosts.Post(id: discussion.id, subject: discussion.subject, message: discussion.message,
                          timecreated: discussion.created, hasparent: false,
                          author: .init(fullname: discussion.userfullname))]
    }
}

// MARK: - Previews

#Preview("Avvisi") {
    CourseForumsView(course: Course.samples[0], kind: .announcements).previewInNavigation()
}


/// The summary's own surface, which only the written summary has: the button
/// before it is a button, not a card.
private struct SummaryCardBackground: ViewModifier {
    /// Whether there is a summary to sit on a card.
    let showing: Bool

    /// The view, on a card or bare.
    ///
    /// - Parameter content: The summary or the button.
    /// - Returns: The view.
    func body(content: Content) -> some View {
        if showing { content.lookCard() } else { content }
    }
}
