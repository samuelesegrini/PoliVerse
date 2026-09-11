import Foundation
import Testing
@testable import PoliVerse

/// The news description arrives as an HTML fragment and reached the screen as
/// literal `<p>` and `&egrave;`.
@Suite("HTML to text")
struct HTMLTextTests {
    @Test("Tags are removed and paragraphs become blank lines")
    func paragraphs() {
        let text = HTMLText.plain("<p>Primo paragrafo.</p><p>Secondo.</p>")
        #expect(text == "Primo paragrafo.\n\nSecondo.")
    }

    @Test("A line break becomes a newline")
    func lineBreaks() {
        #expect(HTMLText.plain("Riga uno<br/>Riga due") == "Riga uno\nRiga due")
    }

    @Test("List items become bullets")
    func lists() {
        let text = HTMLText.plain("<ul><li>Uno</li><li>Due</li></ul>")
        #expect(text.contains("• Uno"))
        #expect(text.contains("• Due"))
    }

    @Test("Italian accented entities decode")
    func italianEntities() {
        #expect(HTMLText.plain("La scadenza &egrave; il 15") == "La scadenza è il 15")
        #expect(HTMLText.plain("Universit&agrave;") == "Università")
        #expect(HTMLText.plain("perch&eacute;") == "perché")
    }

    @Test("Typographic entities decode")
    func typography() {
        #expect(HTMLText.plain("l&rsquo;ateneo") == "l’ateneo")
        #expect(HTMLText.plain("15&ndash;20") == "15–20")
        #expect(HTMLText.plain("e cos&igrave; via&hellip;") == "e così via…")
    }

    @Test("Numeric entities decode in decimal and hex")
    func numericEntities() {
        #expect(HTMLText.plain("caff&#232;") == "caffè")
        #expect(HTMLText.plain("caff&#xE8;") == "caffè")
    }

    /// Order matters: strip tags first, then decode. An author who wrote an
    /// escaped tag meant it as text, and decoding first would turn it into
    /// markup and delete it.
    @Test("An escaped tag survives as text rather than being stripped")
    func escapedTagSurvives() {
        #expect(HTMLText.plain("Usa &lt;div&gt; per i blocchi") == "Usa <div> per i blocchi")
    }

    /// `&amp;egrave;` is a literal ampersand followed by text, not `è`.
    @Test("A double-escaped ampersand stays literal")
    func doubleEscapedAmpersand() {
        #expect(HTMLText.plain("A &amp;egrave; B") == "A &egrave; B")
    }

    @Test("Script and style bodies are dropped, not just their tags")
    func scriptAndStyle() {
        let text = HTMLText.plain("<style>p{color:red}</style><p>Testo</p><script>var x=1</script>")
        #expect(text == "Testo")
    }

    @Test("Source formatting collapses without losing paragraph breaks")
    func whitespaceCollapse() {
        let text = HTMLText.plain("<p>Uno   \n   due</p>\n\n\n<p>Tre</p>")
        #expect(text == "Uno due\n\nTre")
    }

    @Test("Plain text is returned untouched")
    func plainPassesThrough() {
        let plain = "Nessun markup qui: 3 < 5 e costa 10 euro"
        #expect(HTMLText.plainIfNeeded(plain) == plain)
        #expect(!HTMLText.containsMarkup(plain))
    }

    @Test("Markup is detected in both tag and entity form")
    func detection() {
        #expect(HTMLText.containsMarkup("<p>x</p>"))
        #expect(HTMLText.containsMarkup("perch&eacute;"))
    }

    /// The reason this exists, end to end: a news row must read as text.
    @Test("A news description decodes to readable text")
    func newsDescriptionIsReadable() {
        let json = """
        [{"news_id": 1, "title": "Bandi",
          "description": {"it": "<p>Le domande si chiudono il <b>15 febbraio</b>.</p><p>Info sul sito dell&rsquo;ateneo.</p>"}}]
        """
        let items = (try? JSONDecoder().decode(NewsResponse.self, from: Data(json.utf8)))?.items ?? []
        #expect(items.count == 1)
        #expect(items[0].summary == "Le domande si chiudono il 15 febbraio.\n\nInfo sul sito dell’ateneo.")
    }
}
