import SwiftUI

/// Body text that renders its markup when it has any.
///
/// News and notifications both arrive as HTML fragments. Rows show the plain
/// form — two lines of flat text is all they have room for — while a detail
/// view can afford the real thing: bold, italics and tappable links.
struct RichText: View {
    /// The original fragment, when the content carried markup.
    let html: String?
    /// The stripped form, used when it did not.
    let plain: String?

    /// The view's content.
    var body: some View {
        if let html {
            // Rendered on demand rather than stored: an AttributedString is
            // presentation, and keeping one on a model shared with rows would
            // build it for every row that never shows it.
            Text(HTMLText.attributed(html))
                .font(.body)
                .textSelection(.enabled)
        } else if let plain {
            Text(plain)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Previews

#Preview("Testo con markup") {
    ScrollView {
        RichText(
            html: "<p>Le domande si chiudono il <b>15 febbraio</b>.</p>"
                + "<p>Info sul sito dell&rsquo;<a href=\"https://polimi.it\">ateneo</a>.</p>",
            plain: nil)
        .padding()
    }
    .previewEnvironment()
}

#Preview("Testo semplice") {
    RichText(html: nil, plain: "Nessun markup, solo testo.")
        .padding()
        .previewEnvironment()
}
