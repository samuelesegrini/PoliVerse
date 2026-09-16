import SwiftUI

/// A course's announcements, or its discussion forums, from WeBeep.
///
/// Reached from the course page's hub. When the page has more than one
/// discussion forum, each is listed; a single forum opens straight away.
struct CourseForumsView: View {
    let course: Course
    let kind: CourseForum.Kind

    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @State private var forums: [CourseForum]?
    @State private var loaded = false
    @State private var showingLogin = false

    private var title: String {
        kind == .announcements ? String(localized: "Avvisi") : String(localized: "Forum")
    }

    private var tint: Color { Theme.accent(for: course) }

    private var matching: [CourseForum] { (forums ?? []).filter { $0.kind == kind } }

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
                DiscussionsList(forum: forum, tint: tint)
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
                                DiscussionsList(forum: forum, tint: tint).navigationTitle(forum.name)
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
        .courseScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weBeep.isAuthenticated) { await load() }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet { await load() }
        }
    }

    private func load() async {
        guard session.useMockData || weBeep.isAuthenticated else { return }
        forums = await weBeep.forums(for: course)
        loaded = true
    }
}

/// The discussions in one forum, newest activity first as Moodle orders them.
private struct DiscussionsList: View {
    let forum: CourseForum
    let tint: Color

    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale
    @State private var discussions: [MoodleDiscussion]?
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let discussions {
                    if discussions.isEmpty {
                        ContentUnavailableView("Ancora nessun messaggio", systemImage: "bubble.left")
                            .padding(.top, 40)
                    } else {
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
        .courseScreen()
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
    let discussion: MoodleDiscussion
    let tint: Color

    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale
    @State private var posts: [MoodlePosts.Post]?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(discussion.subject ?? discussion.name ?? "")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

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
        .courseScreen()
        .navigationTitle(discussion.subject ?? discussion.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { posts = try? await weBeep.posts(in: discussion) }
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
    CourseForumsView(course: MockData.courses[0], kind: .announcements).previewInNavigation()
}
