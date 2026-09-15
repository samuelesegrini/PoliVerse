import Foundation
import Testing
import UIKit
@testable import PoliVerse

/// The date's typefaces come with iOS: every face a look can ask for must be
/// installed, or the date silently falls back to the system font.
@Suite("Today fonts")
struct TodayFontsTests {
    @Test("Every named face exists, at every weight", arguments: TodayStyle.DateFont.allCases)
    func installed(font: TodayStyle.DateFont) {
        for weight in stride(from: 0.0, through: 1.0, by: 0.1) {
            guard let name = font.faceName(weight: weight) else { continue }
            #expect(UIFont(name: name, size: 20) != nil, "\(name) is not installed")
        }
    }

    @Test("Heavier on the slider is never a lighter face")
    func weightsClimb() {
        for font in TodayStyle.DateFont.allCases {
            let names = stride(from: 0.0, through: 1.0, by: 0.1).compactMap { font.faceName(weight: $0) }
            let order = names.map { name in font.faces.firstIndex(of: name) ?? -1 }
            #expect(order == order.sorted(), "\(font) goes down in weight")
        }
    }

    @Test("There are more faces than the system's four designs, each named")
    func variety() {
        #expect(TodayStyle.DateFont.allCases.count >= 12)
        #expect(TodayStyle.DateFont.allCases.filter { !$0.faces.isEmpty }.count >= 6)
    }
}
