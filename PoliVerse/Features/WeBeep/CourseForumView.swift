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

    private var matching: [CourseForum] { (forums ?? []).filter { $0.kind == kind } }

    var body: some View {
        Group {
            if !session.useMockData && !weBeep.isAuthenticated {
                List {
                    Section {
                        Text("Avvisi e forum arrivano da WeBeep, che usa un accesso separato.")
                            .foregroundStyle(.secondary)
                        Button("Accedi a WeBeep") { showingLogin = true }
                    }
                }
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if forums == nil {
                ContentUnavailableView("WeBeep non risponde", systemImage: "wifi.exclamationmark",
                                       description: Text("Riprova tra poco."))
            } else if matching.count == 1, let forum = matching.first {
                DiscussionsList(forum: forum)
            } else if matching.isEmpty {
                ContentUnavailableView(
                    kind == .announcements ? "Nessun forum avvisi" : "Nessun forum",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("La pagina WeBeep di questo corso non ne ha."))
            } else {
                List(matching) { forum in
                    NavigationLink(forum.name) {
                        DiscussionsList(forum: forum).navigationTitle(forum.name)
                    }
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

    private func load() async {
        guard session.useMockData || weBeep.isAuthenticated else { return }
        forums = await weBeep.forums(for: course)
        loaded = true
    }
}

/// The discussions in one forum, newest activity first as Moodle orders them.
private struct DiscussionsList: View {
    let forum: CourseForum

    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale
    @State private var discussions: [MoodleDiscussion]?
    @State private var failed = false

    var body: some View {
        List {
            if let discussions {
                if discussions.isEmpty {
                    Text("Ancora nessun messaggio.").foregroundStyle(.secondary)
                }
                ForEach(discussions, id: \.id) { discussion in
                    NavigationLink {
                        DiscussionView(discussion: discussion)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if discussion.pinned == true {
                                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                                        .accessibilityLabel("In evidenza")
                                }
                                Text(discussion.subject ?? discussion.name ?? "")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                            }
                            Text(HTMLText.plain(discussion.message ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(caption(discussion))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else if failed {
                Text("Non riesco a leggere questo forum.").foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .refreshable { await load() }
        .task { if discussions == nil { await load() } }
    }

    private func caption(_ discussion: MoodleDiscussion) -> String {
        let when = discussion.created.map {
            Date(timeIntervalSince1970: TimeInterval($0)).formatted(.relative(presentation: .named).locale(locale))
        }
        return [discussion.userfullname, when].compactMap { $0 }.joined(separator: " · ")
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

    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale
    @State private var posts: [MoodlePosts.Post]?

    var body: some View {
        List {
            ForEach(posts ?? fallback) { post in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(post.author?.fullname ?? "")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let created = post.created {
                            Text(created.formatted(.dateTime.day().month().hour().minute().locale(locale)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if post.isReply, let subject = post.subject {
                        Text(subject).font(.caption).foregroundStyle(.secondary)
                    }
                    RichText(html: post.message, plain: nil)
                }
                .padding(.vertical, 4)
                .padding(.leading, post.isReply ? 12 : 0)
            }
            if posts == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
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
