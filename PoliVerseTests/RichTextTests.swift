import Foundation
import Testing
@testable import PoliVerse

/// The rich renderer used by the news and notification detail views.
@Suite("HTML to rich text")
struct RichTextTests {
    private func plainString(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    /// Every run carrying `intent`, as text — enough to assert what is bold
    /// without depending on how the runs happen to be split.
    private func text(with intent: InlinePresentationIntent,
                      in attributed: AttributedString) -> String {
        attributed.runs.reduce(into: "") { result, run in
            if run.inlinePresentationIntent?.contains(intent) == true {
                result += String(attributed[run.range].characters)
            }
        }
    }

    private func links(in attributed: AttributedString) -> [(String, URL)] {
        attributed.runs.compactMap { run in
            guard let link = run.link else { return nil }
            return (String(attributed[run.range].characters), link)
        }
    }

    @Test("Bold and italic become presentation intents")
    func emphasis() {
        let rich = HTMLText.attributed("Scadenza <b>15 febbraio</b> e <i>non oltre</i>")
        #expect(plainString(rich) == "Scadenza 15 febbraio e non oltre")
        #expect(text(with: .stronglyEmphasized, in: rich) == "15 febbraio")
        #expect(text(with: .emphasized, in: rich) == "non oltre")
    }

    @Test("strong and em are treated as bold and italic")
    func synonyms() {
        let rich = HTMLText.attributed("<strong>A</strong><em>B</em>")
        #expect(text(with: .stronglyEmphasized, in: rich) == "A")
        #expect(text(with: .emphasized, in: rich) == "B")
    }

    @Test("Nested emphasis carries both intents")
    func nestedEmphasis() {
        let rich = HTMLText.attributed("<b><i>importante</i></b>")
        #expect(text(with: .stronglyEmphasized, in: rich) == "importante")
        #expect(text(with: .emphasized, in: rich) == "importante")
    }

    @Test("A link becomes a tappable run over its own text")
    func anchors() {
        let rich = HTMLText.attributed("Vedi <a href=\"https://www.polimi.it/bandi\">il bando</a> online")
        #expect(plainString(rich) == "Vedi il bando online")
        let found = links(in: rich)
        #expect(found.count == 1)
        #expect(found.first?.0 == "il bando")
        #expect(found.first?.1.absoluteString == "https://www.polimi.it/bandi")
    }

    @Test("Single-quoted and unquoted hrefs are read")
    func hrefQuoting() {
        #expect(links(in: HTMLText.attributed("<a href='https://polimi.it'>x</a>")).count == 1)
        #expect(links(in: HTMLText.attributed("<a href=https://polimi.it>x</a>")).count == 1)
    }

    /// There is no base URL to resolve a relative href against, and a link
    /// that goes nowhere is worse than text that is plainly not a link.
    @Test("A relative href is dropped rather than guessed at")
    func relativeHrefDropped() {
        let rich = HTMLText.attributed("<a href=\"/bandi\">il bando</a>")
        #expect(plainString(rich) == "il bando")
        #expect(links(in: rich).isEmpty)
    }

    @Test("Link text keeps its own emphasis")
    func emphasisedLink() {
        let rich = HTMLText.attributed("<a href=\"https://polimi.it\"><b>Iscriviti</b></a>")
        #expect(links(in: rich).first?.0 == "Iscriviti")
        #expect(text(with: .stronglyEmphasized, in: rich) == "Iscriviti")
    }

    @Test("Paragraphs and breaks survive as newlines")
    func structure() {
        let rich = HTMLText.attributed("<p>Uno</p><p>Due<br>Tre</p>")
        #expect(plainString(rich) == "Uno\n\nDue\nTre")
    }

    @Test("Entities are decoded in rich text too")
    func entities() {
        #expect(plainString(HTMLText.attributed("La scadenza &egrave; l&rsquo;11")) == "La scadenza è l’11")
    }

    /// Same ordering guarantee as the plain path: an escaped tag is text.
    @Test("An escaped tag stays text and is not treated as markup")
    func escapedTag() {
        let rich = HTMLText.attributed("Usa &lt;b&gt; per il grassetto")
        #expect(plainString(rich) == "Usa <b> per il grassetto")
        #expect(text(with: .stronglyEmphasized, in: rich).isEmpty)
    }

    @Test("Unknown tags are ignored rather than shown")
    func unknownTags() {
        let rich = HTMLText.attributed("<span class=\"x\">Testo</span><figure><img src=\"a.jpg\"></figure>")
        #expect(plainString(rich) == "Testo")
    }

    @Test("Source wrapping collapses to spaces, as in HTML")
    func wrapping() {
        let rich = HTMLText.attributed("<p>Uno\n   due</p>")
        #expect(plainString(rich) == "Uno due")
    }

    @Test("Script and style bodies never reach the output")
    func scriptAndStyle() {
        let rich = HTMLText.attributed("<style>p{color:red}</style><p>Testo</p>")
        #expect(plainString(rich) == "Testo")
    }

    @Test("List items become bullet lines")
    func lists() {
        let rich = HTMLText.attributed("<ul><li>Uno</li><li>Due</li></ul>")
        #expect(plainString(rich) == "• Uno\n• Due")
    }

    @Test("An unclosed tag does not swallow the rest of the text")
    func unclosedTag() {
        #expect(plainString(HTMLText.attributed("Testo < non una tag")) == "Testo < non una tag")
    }

    @Test("Plain text renders unchanged")
    func plainPassesThrough() {
        #expect(plainString(HTMLText.attributed("Nessun markup")) == "Nessun markup")
    }

    /// The rich and plain paths must agree on the words; only formatting
    /// differs between them.
    @Test("Rich and plain renderings carry the same text")
    func richMatchesPlain() {
        let html = "<p>Le domande si chiudono il <b>15 febbraio</b>.</p><p>Info sul sito dell&rsquo;<a href=\"https://polimi.it\">ateneo</a>.</p>"
        #expect(plainString(HTMLText.attributed(html)) == HTMLText.plain(html))
    }
}
