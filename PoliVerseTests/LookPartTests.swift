import Foundation
import Testing
@testable import PoliVerse

/// Personalizza's parts: each resets on its own, a theme keeps the look's app
/// and the name given to it, and undo takes a burst of changes back as one.
@MainActor
@Suite("Look parts")
struct LookPartTests {
    /// A look with something changed in every part.
    private func edited(from original: TodayStyle) throws -> TodayStyle {
        var look = original
        look.flavor = try #require(Flavor(hex: "#C2386F"))
        look.appearance = .dark
        look.paper = .plot
        look.grain = 0.5
        look.dateFont = .mono
        look.bar.showsProfile = false
        look.showsGreeting = false
        look.accessory = .text
        look.material = .glow
        look.app.paired = false
        return look
    }

    @Test("A classic look has seven parts; a special Flavor its knobs between Tema and App")
    func parts() {
        #expect(LookPart.parts(for: TodayStyle()) == [.theme, .colour, .background, .date, .greeting, .cards, .app])
        #expect(LookPart.parts(for: .starting(.blueprint)) == [.theme, .special, .app])
    }

    @Test("Every tool belongs to one part, and a zone opens the part it shows")
    func tools() {
        for part in LookPart.allCases {
            for page in part.tools {
                #expect(LookPart(page: page) == part)
            }
        }
        #expect(LookPart.opening(.date, in: TodayStyle())?.part == .date)
        #expect(LookPart.opening(.stickers, in: TodayStyle())?.page == .accessory)
        #expect(LookPart.opening(.section(.upcoming), in: TodayStyle()) == nil)
        #expect(LookPart.opening(.date, in: .starting(.blueprint))?.part == .special)
    }

    @Test("Resetting a part puts back only that part")
    func reset() throws {
        let original = TodayStyle()
        let look = try edited(from: original)

        let colour = LookPart.colour.reset(look, to: original)
        #expect(colour.flavor == original.flavor)
        #expect(colour.appearance == original.appearance)
        #expect(colour.dateFont == look.dateFont, "Resetting the colours reset the date")

        let date = LookPart.date.reset(look, to: original)
        #expect(date.dateFont == original.dateFont)
        #expect(date.bar == original.bar)
        #expect(date.flavor == look.flavor)

        let background = LookPart.background.reset(look, to: original)
        #expect(background.paper == original.paper)
        #expect(background.grain == original.grain)

        let greeting = LookPart.greeting.reset(look, to: original)
        #expect(greeting.showsGreeting == original.showsGreeting)
        #expect(greeting.accessory == original.accessory)

        #expect(LookPart.cards.reset(look, to: original).material == original.material)
        #expect(LookPart.app.reset(look, to: original).app == original.app)

        // Tema puts back the page, but not the app.
        let theme = LookPart.theme.reset(look, to: original)
        #expect(theme.flavor == original.flavor)
        #expect(theme.app == look.app)

        // Every part reset in turn is the look editing found, and a part
        // already as it was changes nothing.
        let all = LookPart.allCases.reduce(look) { $1.reset($0, to: original) }
        #expect(all == original)
        #expect(LookPart.colour.reset(original, to: original) == original)
    }

    @Test("A theme keeps the look's app and the name the student gave it")
    func wearing() throws {
        let theme = try #require(TodayStyle.presets.last)
        var look = TodayStyle()
        look.app.paired = false
        look.name = "Mio"
        let worn = look.wearing(theme)
        #expect(worn.flavor == theme.flavor)
        #expect(worn.app == look.app)
        #expect(worn.name == "Mio")

        // A name that came with another theme goes with it.
        let first = try #require(TodayStyle.presets.first { !$0.name.isEmpty && $0.name != theme.name })
        #expect(TodayStyle().wearing(first).wearing(theme).name == theme.name)
    }

    @Test("Undo takes a burst of changes back as one, and redo brings it again")
    func history() throws {
        var history = EditHistory()
        let start = TodayStyle()
        var look = start
        let now = Date.now

        // Three quick changes, like a slider dragged.
        for (step, grain) in [0.2, 0.4, 0.6].enumerated() {
            let old = look
            look.grain = grain
            history.record(old, at: now.addingTimeInterval(Double(step) * 0.1))
        }
        // Then one a while later.
        let beforeFont = look
        look.dateFont = .mono
        history.record(beforeFont, at: now.addingTimeInterval(5))

        let undone = try #require(history.undo(from: look))
        #expect(undone == beforeFont)
        // The undo's own change arrives and is not an edit.
        history.record(look)
        look = undone

        let first = try #require(history.undo(from: look))
        #expect(first == start, "The slider's burst took more than one undo")
        history.record(look)
        look = first
        #expect(!history.canUndo)

        let redone = try #require(history.redo(from: look))
        #expect(redone == beforeFont)
        history.record(look)
        look = redone
        #expect(history.canRedo)

        // A new change drops what could be redone.
        let old = look
        look.material = .glow
        history.record(old)
        #expect(!history.canRedo)
    }
}
