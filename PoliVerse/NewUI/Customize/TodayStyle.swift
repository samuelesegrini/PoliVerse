import SwiftUI

/// How the Oggi page looks: the student's choices from Personalizza.
///
/// Few, curated options with one fine control each, like the Lock Screen
/// clock: a handful of typefaces, a weight slider and a row of colours.
nonisolated struct TodayStyle: Equatable, Sendable {
    init() {}

    nonisolated enum DateFont: String, Codable, CaseIterable, Identifiable, Sendable {
        case expanded, rounded, serif, mono
        var id: String { rawValue }

        @MainActor func font(size: CGFloat, weight: Font.Weight) -> Font {
            switch self {
            case .expanded: .system(size: size, weight: weight).width(.expanded)
            case .rounded: .system(size: size, weight: weight, design: .rounded)
            case .serif: .system(size: size, weight: weight, design: .serif)
            case .mono: .system(size: size, weight: weight, design: .monospaced)
            }
        }
    }

    nonisolated enum Accent: String, Codable, CaseIterable, Identifiable, Sendable {
        case ink, polimi, orange, violet, rose, green
        var id: String { rawValue }

        @MainActor var color: Color {
            switch self {
            case .ink: .primary
            case .polimi: Theme.brand
            case .orange: Color(red: 0.91, green: 0.46, blue: 0.10)
            case .violet: Color(red: 0.44, green: 0.39, blue: 0.85)
            case .rose: Color(red: 0.85, green: 0.33, blue: 0.48)
            case .green: Color(red: 0.25, green: 0.56, blue: 0.40)
            }
        }
    }

    var dateFont: DateFont = .expanded
    /// 0 is regular, 1 is black.
    var dateWeight: Double = 1
    var dateAccent: Accent = .ink
    var showsGreeting = true
    var showsUpcoming = true
    var showsTimetable = true

    var weight: Font.Weight {
        let steps: [Font.Weight] = [.regular, .medium, .semibold, .bold, .heavy, .black]
        return steps[min(Int((dateWeight * Double(steps.count - 1)).rounded()), steps.count - 1)]
    }

    static let storageKey = "todayStyle"
    static let libraryKey = "todayStyleLibrary"
    static let selectionKey = "todayStyleSelection"

    /// The looks offered before the student makes any: the default, a warm
    /// one, a quiet serif and a minimal page with only the timetable.
    static var presets: [TodayStyle] {
        var warm = TodayStyle()
        warm.dateAccent = .orange
        warm.dateFont = .rounded
        var serif = TodayStyle()
        serif.dateFont = .serif
        serif.dateWeight = 0.5
        serif.dateAccent = .polimi
        var minimal = TodayStyle()
        minimal.dateFont = .mono
        minimal.dateWeight = 0.2
        minimal.showsGreeting = false
        minimal.showsUpcoming = false
        return [TodayStyle(), warm, serif, minimal]
    }

    /// Saved looks, one stored style per line; the presets when there are none.
    static func library(from stored: String, active: TodayStyle) -> [TodayStyle] {
        let looks = stored.split(separator: "\n").compactMap { TodayStyle(rawValue: String($0)) }
        return looks.isEmpty ? presets : looks
    }

    static func encodeLibrary(_ looks: [TodayStyle]) -> String {
        looks.map(\.rawValue).joined(separator: "\n")
    }
}

/// What is stored: the same fields in a plain Codable struct. Kept apart
/// from `TodayStyle` because a `RawRepresentable` string type picks up the
/// standard library's Codable, which encodes `rawValue` instead.
nonisolated private struct StoredTodayStyle: Codable {
    var dateFont: TodayStyle.DateFont?
    var dateWeight: Double?
    var dateAccent: TodayStyle.Accent?
    var showsGreeting: Bool?
    var showsUpcoming: Bool?
    var showsTimetable: Bool?
}

nonisolated extension TodayStyle: RawRepresentable {
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredTodayStyle.self, from: data) else { return nil }
        self.init()
        dateFont = stored.dateFont ?? dateFont
        dateWeight = stored.dateWeight ?? dateWeight
        dateAccent = stored.dateAccent ?? dateAccent
        showsGreeting = stored.showsGreeting ?? showsGreeting
        showsUpcoming = stored.showsUpcoming ?? showsUpcoming
        showsTimetable = stored.showsTimetable ?? showsTimetable
    }

    var rawValue: String {
        let stored = StoredTodayStyle(dateFont: dateFont, dateWeight: dateWeight, dateAccent: dateAccent,
                                      showsGreeting: showsGreeting, showsUpcoming: showsUpcoming,
                                      showsTimetable: showsTimetable)
        return (try? String(data: JSONEncoder().encode(stored), encoding: .utf8)) ?? "{}"
    }
}
