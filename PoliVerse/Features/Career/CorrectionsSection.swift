import SwiftUI

/// The marked scripts for one sitting, and a way to open each on Servizi
/// Online.
///
/// The sitting's `hasCorrezioni` flag has always been shown as a sentence
/// telling the student to go and look on the web. This lists what is actually
/// there.
///
/// The documents themselves are not downloaded. `/v1/prove/correzione/{id}`
/// answers a blob whose type is not documented, and a marked script can carry
/// other students' work in the same file — see `docs/academic-intelligence-layer.md`
/// on minimisation. Opening on Servizi Online keeps the file where the
/// university serves it.
struct CorrectionsSection: View {
    /// The sitting whose corrections these are.
    let exam: ExamSession

    /// The shared ``Session``, from the environment, which is the account the
    /// call is made as.
    @Environment(Session.self) private var session
    /// Opens Servizi Online in the browser.
    @Environment(\.openURL) private var openURL

    /// What has been read, or `nil` before the first reading.
    @State private var corrections: [Correction]?
    /// Set when the service refused, so the screen says so rather than
    /// claiming there is nothing.
    @State private var refused = false

    /// The view's content.
    var body: some View {
        if exam.hasCorrections, !session.useMockData {
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Elaborato corretto")
                content
            }
            .task(id: exam.id) { await load() }
        }
    }

    /// The list, the wait, or the sentence that stands in for either.
    @ViewBuilder
    private var content: some View {
        switch (corrections, refused) {
        case (nil, false):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Cerco l'elaborato…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .lookCard()
        case (let list?, _) where !list.isEmpty:
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, correction in
                    row(correction, last: index == list.count - 1)
                }
            }
            .lookCard()
        default:
            // Either the service refused, or it answered something this
            // reader could not use. Both mean the same thing to the student:
            // look on the web.
            Label("Consultabile sui Servizi Online.", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .lookCard()
        }
    }

    /// One document.
    ///
    /// - Parameters:
    ///   - correction: The document.
    ///   - last: Whether it is the last row, which draws no separator.
    /// - Returns: The row.
    private func row(_ correction: Correction, last: Bool) -> some View {
        Button {
            openURL(Self.serviziOnline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(correction.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if let date = correction.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Divider().padding(.leading, 48) }
        }
    }

    /// Servizi Online, where the marked script is actually served.
    ///
    /// The deep link to one document is not known — `docs/polimi-api-research.md`
    /// §4c has the API path and nothing about the web app's own routes — so the
    /// link opens the service rather than guessing a URL that would land on an
    /// error page.
    static let serviziOnline = URL(string: "https://www.polimi.it/servizionline")!

    /// Reads the list, once per sitting.
    private func load() async {
        guard corrections == nil else { return }
        do {
            corrections = try await CorrectionsSource.corrections(forExam: exam.id, http: session.http)
        } catch {
            refused = true
        }
    }
}
