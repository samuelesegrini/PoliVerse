import SwiftUI

/// The notification inbox, reached from the bell on the Home screen.
struct NoticesView: View {
    @Environment(NoticeService.self) private var notices
    @Environment(\.dismiss) private var dismiss

    /// Shown inside a navigation stack that is not its own.
    private let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        RootStack(embedded: embedded) {
            Group {
                if let message = notices.errorMessage, notices.notices.isEmpty {
                    ContentUnavailableView("Notifiche non disponibili",
                                           systemImage: "bell.slash",
                                           description: Text(message))
                } else if notices.payloadUnreadable {
                    // Deliberately not "nessuna notifica": the server answered
                    // with something this app could not read, and presenting
                    // that as an empty inbox would hide a real problem behind
                    // a reassuring screen.
                    ContentUnavailableView(
                        "Formato non riconosciuto",
                        systemImage: "questionmark.circle",
                        description: Text("Il Politecnico ha risposto in un formato che PoliVerse non sa ancora leggere."))
                } else if notices.notices.isEmpty && !notices.isLoading {
                    ContentUnavailableView("Nessuna notifica", systemImage: "bell",
                                           description: Text("Le comunicazioni dal Politecnico compaiono qui."))
                } else {
                    list
                }
            }
            .navigationTitle("Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Chiudi") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Segna tutte") { notices.markAllRead() }
                        .disabled(notices.unreadCount == 0)
                }
            }
            .task { await notices.load() }
            .refreshable { await notices.load(force: true) }
        }
    }

    private var list: some View {
        List {
            Section {
                PageHero(symbol: "megaphone", title: Text("Notifiche"), summary: notices.unreadCount > 0 ? Text("\(notices.unreadCount) da leggere") : Text("Tutto letto"))
                    .listHeader()
            }
            Section {
                ForEach(notices.notices) { notice in
                    NavigationLink {
                        NoticeDetailView(notice: notice)
                    } label: {
                        NoticeRow(notice: notice)
                    }
                }
            }
            .glassRow()
        }
        .glassList()
    }
}

private struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // An unread dot rather than bold text alone: weight is easy to
            // miss, and this is the one thing the row has to communicate.
            Circle()
                .fill(notice.isRead ? .clear : Theme.brand)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.subheadline.weight(notice.isRead ? .regular : .semibold))
                    .lineLimit(2)

                if let body = notice.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if let category = notice.category {
                        Text(category)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.brand.opacity(0.12), in: .capsule)
                    }
                    if let date = notice.date {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.isRead ? notice.title : "Non letta. \(notice.title)")
    }
}

/// One notice in full.
///
/// The list may carry only a summary, so the detail endpoint is asked for the
/// whole text — and if that call fails, the summary stays on screen rather
/// than the view going blank.
struct NoticeDetailView: View {
    let notice: Notice
    @Environment(NoticeService.self) private var notices
    @Environment(\.openURL) private var openURL

    /// The detail endpoint's body, markup intact.
    @State private var fullText: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(notice.title)
                    .font(.title2.weight(.bold))

                if let date = notice.date {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isLoading && fullText == nil && notice.body == nil {
                    ProgressView()
                }

                // The detail call's text wins where it arrived; otherwise
                // the summary from the list stands.
                if let markup = fullText ?? notice.bodyHTML {
                    RichText(html: markup, plain: notice.body)
                } else {
                    RichText(html: nil, plain: notice.body)
                }

                if let link = notice.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Apri sul sito", systemImage: "safari")
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .lookCard(cornerRadius: 30)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .courseScreen()
        .navigationTitle("Notifica")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Opening it is what marks it read; there is no write to the
            // university system behind this, only what this device remembers.
            notices.markRead(notice)
            guard fullText == nil else { return }
            isLoading = true
            fullText = await notices.detail(for: notice)
            isLoading = false
        }
    }
}

/// The bell, with its unread count, for the Home toolbar.
struct NoticesToolbarButton: View {
    @Environment(NoticeService.self) private var notices
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: notices.unreadCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel(
            notices.unreadCount > 0
                ? "Notifiche, \(notices.unreadCount) non lette"
                : "Notifiche")
    }
}

// MARK: - Previews

#Preview("Notifiche") {
    NoticesView().previewEnvironment()
}

#Preview("Notifica") {
    NoticeDetailView(notice: MockData.notices()[0]).previewInNavigation()
}

#Preview("Componente · Riga notifica") {
    List {
        ForEach(MockData.notices()) { NoticeRow(notice: $0) }
    }
    .listStyle(.plain)
    .previewEnvironment()
}
