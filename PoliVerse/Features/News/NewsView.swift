import SwiftUI

/// The full news list.
struct NewsView: View {
    @Environment(NewsModel.self) private var news

    var body: some View {
        Group {
            if let message = news.errorMessage, news.items.isEmpty {
                ContentUnavailableView("Notizie non disponibili",
                                       systemImage: "newspaper",
                                       description: Text(message))
            } else if news.payloadUnreadable {
                // Not "nessuna notizia": the server answered with something
                // unreadable, and dressing that as an empty feed would hide it.
                ContentUnavailableView(
                    "Formato non riconosciuto",
                    systemImage: "questionmark.circle",
                    description: Text("Il Politecnico ha risposto in un formato che PoliVerse non sa ancora leggere."))
            } else if news.items.isEmpty && !news.isLoading {
                ContentUnavailableView("Nessuna notizia", systemImage: "newspaper",
                                       description: Text("Le notizie dal Politecnico compaiono qui."))
            } else {
                List {
                    Section {
                        PageHero(symbol: "newspaper", title: Text("Notizie"), summary: Text("Dal Politecnico"))
                            .listHeader()
                    }
                    Section {
                        ForEach(news.items) { item in
                            NavigationLink {
                                NewsDetailView(item: item)
                            } label: {
                                NewsRow(item: item)
                            }
                        }
                    }
                    .glassRow()
                }
                .glassList()
            }
        }
        .navigationTitle("Notizie")
        .navigationBarTitleDisplayMode(.inline)
        .task { await news.load() }
        .refreshable { await news.load(force: true) }
    }
}

private struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
            if let summary = item.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if let category = item.category {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.brand.opacity(0.12), in: .capsule)
                }
                if let date = item.displayDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct NewsDetailView: View {
    let item: NewsItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Loaded only when there is one; a news feed without images is
                // the likelier case and must not leave a gap.
                if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(height: 180)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 12))
                }

                Text(item.title)
                    .font(.title2.weight(.bold))

                if let date = item.eventStart {
                    // An announced event gets its full span, since "when" is
                    // the whole question for a seminar or a deadline.
                    Label(NewsItem.span(from: date, to: item.eventEnd),
                          systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                } else if let published = item.published {
                    Text(published.formatted(date: .long, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                RichText(html: item.summaryHTML, plain: item.summary)

                if let link = item.link {
                    Button {
                        openURL(link)
                    } label: {
                        Label("Leggi sul sito", systemImage: "safari")
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
        .navigationTitle("Notizia")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Home section: a few headlines, with a way through to the rest.
struct NewsHighlights: View {
    @Environment(NewsModel.self) private var news

    var body: some View {
        // Silent when there is nothing: an error banner for news would push
        // the timetable and courses down the screen for the least urgent
        // thing on it.
        if !news.highlights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dal Politecnico")
                        .font(.headline)
                    Spacer()
                    NavigationLink("Tutte") { NewsView() }
                        .font(.subheadline)
                }

                ForEach(news.highlights) { item in
                    NavigationLink {
                        NewsDetailView(item: item)
                    } label: {
                        NewsHighlightCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct NewsHighlightCard: View {
    let item: NewsItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.brand)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let date = item.displayDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Previews

#Preview("Notizie") {
    NewsView().previewInNavigation()
}

#Preview("Notizia") {
    NewsDetailView(item: NewsItem.samples()[0]).previewInNavigation()
}

#Preview("In evidenza") {
    ScrollView { NewsHighlights().padding() }.previewInNavigation()
}

#Preview("Componente · Riga notizia") {
    List {
        ForEach(NewsItem.samples()) { NewsRow(item: $0) }
    }
    .listStyle(.plain)
    .previewEnvironment()
}

#Preview("Componente · Card notizia") {
    VStack(spacing: 10) {
        ForEach(NewsItem.samples()) { NewsHighlightCard(item: $0) }
    }
    .padding()
    .previewEnvironment()
}
