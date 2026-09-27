import Foundation
import Testing
@testable import PoliVerse

/// Stickers beside the date: where they land, how far they can be pushed, and
/// the files their images are kept in.
@Suite("Today stickers")
struct TodayStickersTests {
    @Test("The first sticker turns the header into date and stickers, in the middle of the panel")
    func firstSticker() throws {
        var style = TodayStyle()
        #expect(style.accessory == .none)
        let addedSticker = style.addSticker(.emoji("🎓"))
        let sticker = try #require(addedSticker)
        #expect(style.accessory == .stickers)
        #expect(sticker.x == 0.5 && sticker.y == 0.5)
        #expect(style.stickers == [sticker])
    }

    @Test("Later stickers land in different places, and the panel holds a fixed number")
    func spreadAndLimit() {
        var style = TodayStyle()
        for index in 0..<TodayStyle.maxStickers {
            let added = style.addSticker(.emoji("\(index)"))
            #expect(added != nil)
        }
        let spots = Set(style.stickers.map { "\($0.x),\($0.y)" })
        #expect(spots.count == TodayStyle.maxStickers)
        let overflow = style.addSticker(.emoji("🚫"))
        #expect(overflow == nil)
        #expect(style.stickers.count == TodayStyle.maxStickers)
    }

    @Test("Moving, resizing and turning are kept inside the panel")
    func clamped() throws {
        var style = TodayStyle()
        let addedSticker = style.addSticker(.emoji("⭐️"))
        let sticker = try #require(addedSticker)
        style.updateSticker(sticker.id) {
            $0.x = 3
            $0.y = -1
            $0.size = 9
            $0.rotation = 400
        }
        let moved = try #require(style.stickers.first)
        #expect(moved.x == 1 && moved.y == 0)
        #expect(moved.size == PlacedSticker.sizes.upperBound)
        #expect(moved.rotation == 40)
    }

    @Test("A new sticker avoids one moved onto a free spot")
    func avoidsMoved() throws {
        var style = TodayStyle()
        let added = style.addSticker(.emoji("1"))
        let first = try #require(added)
        style.updateSticker(first.id) { $0.x = 0.25; $0.y = 0.3 }
        let second = style.addSticker(.emoji("2"))
        let next = try #require(second)
        #expect(!(next.x == 0.25 && next.y == 0.3))
    }

    @Test("Removing a sticker leaves the others; the images in use are listed for the store")
    func removeAndImages() throws {
        var style = TodayStyle()
        let addedEmoji = style.addSticker(.emoji("☕️"))
        let emoji = try #require(addedEmoji)
        _ = style.addSticker(.image("A"))
        _ = style.addSticker(.image("B"))
        style.removeSticker(emoji.id)
        #expect(style.stickers.count == 2)
        #expect(style.storedImageIDs == ["A", "B"])
    }

    @Test("Stickers and the header round-trip through the stored string")
    func roundTrip() throws {
        var style = TodayStyle()
        _ = style.addSticker(.image("glyph"))
        _ = style.addSticker(.emoji("🧪"))
        let restored = try #require(TodayStyle(rawValue: style.rawValue))
        #expect(restored.accessory == .stickers)
        #expect(restored.stickers == style.stickers)
    }

    @Test("The store saves an image, reads it back and forgets the ones no look uses")
    func store() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stickers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StickerStore(directory: directory)

        let kept = try store.save(Data([1, 2, 3]))
        let dropped = try store.save(Data([4, 5]))
        #expect(kept != dropped)
        #expect(store.data(for: kept) == Data([1, 2, 3]))

        store.prune(keeping: [kept])
        #expect(store.data(for: kept) != nil)
        #expect(store.data(for: dropped) == nil)
        #expect(store.data(for: "missing") == nil)
    }

    @Test("The selected sticker's actions size, turn, copy, raise and remove it")
    func edits() throws {
        var style = TodayStyle()
        // Called first: `#require` cannot wrap a mutating call.
        let firstAdded = style.addSticker(.emoji("🎓"))
        let first = try #require(firstAdded)
        let secondAdded = style.addSticker(.emoji("📚"))
        let second = try #require(secondAdded)

        style.edit(sticker: first.id, .bigger)
        #expect(style.stickers[0].size == first.size + StickerEdit.sizeStep)
        style.edit(sticker: first.id, .smaller)
        style.edit(sticker: first.id, .smaller)
        #expect(abs(style.stickers[0].size - (first.size - StickerEdit.sizeStep)) < 0.0001)

        // Ruota goes round: past the last turn one way, back to the other.
        style.updateSticker(first.id) { $0.rotation = PlacedSticker.rotations.upperBound }
        style.edit(sticker: first.id, .turn)
        #expect(style.stickers[0].rotation == PlacedSticker.rotations.lowerBound)

        // The copy is selected, a little off the original so both show.
        let copied = style.edit(sticker: first.id, .duplicate)
        let copy = try #require(copied)
        #expect(copy != first.id)
        #expect(style.stickers.count == 3)
        #expect(style.stickers.last?.content == first.content)
        #expect(style.stickers.last?.x ?? 0 > style.stickers[0].x)

        // In primo piano draws it last, over the others.
        style.edit(sticker: first.id, .front)
        #expect(style.stickers.last?.id == first.id)
        #expect(style.stickers.first?.id == second.id)

        #expect(style.edit(sticker: first.id, .remove) == nil)
        #expect(!style.stickers.contains { $0.id == first.id })
        #expect(style.edit(sticker: first.id, .bigger) == nil, "A sticker no longer there was still selected")
    }

    @Test("A full panel takes no copy, and keeps the sticker selected")
    func fullPanel() throws {
        var style = TodayStyle()
        for _ in 0..<TodayStyle.maxStickers { style.addSticker(.emoji("⭐️")) }
        let id = try #require(style.stickers.first?.id)
        #expect(style.edit(sticker: id, .duplicate) == id)
        #expect(style.stickers.count == TodayStyle.maxStickers)
    }
}
