import Foundation
import Testing
@testable import PoliVerse

/// The identifier a Spotlight hit comes back as.
///
/// Spotlight hands back this string and nothing else, possibly months after
/// the app last ran, so the string alone has to say which screen to open and
/// which thing to open it on. A round trip that loses part of an id opens the
/// wrong room.
@Suite("Identificativi per Spotlight")
struct SpotlightItemTests {
    private typealias Item = SpotlightIndex.Item

    @Test("Ogni tipo si riconosce dal suo identificativo", arguments: [
        Item.course("085923"), Item.room("3.1.4"), Item.teacher("rossi-matteo"), Item.exam("41287"),
    ])
    func roundTrip(item: Item) {
        #expect(Item(identifier: item.identifier) == item)
    }

    @Test("Il tipo è scritto davanti, l’identificativo dietro")
    func shape() {
        #expect(Item.course("085923").identifier == "course:085923")
        #expect(Item.room("3.1.4").identifier == "room:3.1.4")
        #expect(Item.teacher("rossi-matteo").identifier == "teacher:rossi-matteo")
        #expect(Item.exam("41287").identifier == "exam:41287")
    }

    /// The value is split off once, so an id that contains a colon of its own
    /// comes back whole rather than truncated.
    @Test("Un identificativo che contiene i due punti resta intero")
    func colonInTheValue() {
        let item = Item.teacher("polimi:rossi:matteo")
        #expect(Item(identifier: item.identifier) == item)
    }

    /// Anything else in the index — an identifier from an older release, or a
    /// string that was never one of ours — is refused rather than routed to a
    /// screen that cannot show it.
    @Test("Un identificativo estraneo non apre niente", arguments: [
        "", "course", "085923", ":085923", "news:1", "corso:085923",
    ])
    func unknown(identifier: String) {
        #expect(Item(identifier: identifier) == nil)
    }

    /// A type with nothing after it is refused: the split drops the empty
    /// half, so there is no id to open anything on.
    @Test("Un tipo senza identificativo non apre niente")
    func emptyValue() {
        #expect(Item(identifier: "course:") == nil)
    }
}
