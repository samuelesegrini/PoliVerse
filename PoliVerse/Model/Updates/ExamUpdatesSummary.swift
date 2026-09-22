import Foundation

/// What Siri says when asked for news about exams.
///
/// Titles and teaching names only, never a mark: Siri answers out loud, so the details
/// stay in the app. A week rather than the feed's fortnight, because that is what a
/// spoken answer can promise.
nonisolated enum ExamUpdatesSummary {
    /// How many updates are named out loud; the rest become a count.
    static let spokenLimit = 3

    /// The spoken answer for the week's exam news.
    ///
    /// Ordinary course material is left out, and a mark read from a file that the exam
    /// services have since confirmed is not counted twice.
    ///
    /// - Parameters:
    ///   - updates: The recorded updates.
    ///   - now: The moment the week is measured back from.
    /// - Returns: The sentence to speak.
    static func spoken(_ updates: [ExamUpdate], now: Date) -> String {
        let week = updates.filter {
            $0.detectedAt > now.addingTimeInterval(-7 * 86400) && $0.kind != .materialAdded
        }
        // A file's mark the exam services have since confirmed is not a
        // second piece of news.
        let items = FeedItem.items(from: week.sorted { $0.detectedAt > $1.detectedAt })
            .filter { !$0.isSuperseded }
        guard !items.isEmpty else {
            return String(localized: "Nessuna novità sui tuoi esami questa settimana.")
        }
        let lines = items.prefix(spokenLimit).map { "\($0.update.title): \($0.update.courseName)." }
        return ([String(localized: "\(items.count) novità sui tuoi esami questa settimana.")] + lines)
            .joined(separator: " ")
    }
}

/// What Siri says when asked for the next exam.
nonisolated enum NextExamSummary {
    /// The spoken answer for the next sitting, read from the widgets' snapshot.
    ///
    /// A sitting with no time of day — which the services express as midnight in Rome — is
    /// named by its day alone rather than claiming it begins at midnight.
    ///
    /// - Parameters:
    ///   - snapshot: The career snapshot, or `nil` when none has been written.
    ///   - now: The moment to measure from.
    ///   - locale: The locale the date is formatted in.
    /// - Returns: The sentence to speak.
    static func spoken(_ snapshot: CareerSnapshot?, now: Date, locale: Locale = .current) -> String {
        guard let snapshot, let name = snapshot.nextExamName, let date = snapshot.nextExamDate, date > now else {
            return String(localized: "Non risultano appelli in programma.")
        }
        var style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale)
        style.timeZone = PoliMiDate.romeCalendar.timeZone
        let day = date.formatted(style)
        let midnight = PoliMiDate.romeCalendar.startOfDay(for: date) == date
        guard !midnight else { return String(localized: "Il prossimo appello è \(name), \(day).") }
        var clock = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        clock.timeZone = PoliMiDate.romeCalendar.timeZone
        return String(localized: "Il prossimo appello è \(name), \(day) alle \(date.formatted(clock)).")
    }
}
