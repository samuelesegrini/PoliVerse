import SwiftUI

/// What the line above the date says.
nonisolated enum GreetingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// "Buona giornata!"
    case classic
    /// Changes with the hour: good morning, afternoon, evening, night.
    case timeOfDay
    /// "Ciao, Samuele".
    case name
    /// A short line that changes each day.
    case motto
    /// Week of the year and how far into it the day is.
    case week
    /// The student's own words.
    case custom

    /// The greeting's identity, which is its raw value.
    var id: String { rawValue }

    /// What the greeting is called in Personalizza.
    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classico"
        case .timeOfDay: "Secondo l’ora"
        case .name: "Con il nome"
        case .motto: "Frase del giorno"
        case .week: "Settimana"
        case .custom: "Personalizzato"
        }
    }

    /// The line itself.
    func text(for day: Date, now: Date = .now, firstName: String?, custom: String = "",
              calendar: Calendar = PoliMiDate.romeCalendar) -> String {
        switch self {
        case .custom:
            let line = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? GreetingStyle.classic.text(for: day, firstName: firstName) : line
        case .classic:
            return String(localized: "Buona giornata!")
        case .timeOfDay:
            let name = firstName.map { ", \($0)" } ?? ""
            switch calendar.component(.hour, from: now) {
            case 5..<12: return String(localized: "Buongiorno\(name)!")
            case 12..<18: return String(localized: "Buon pomeriggio\(name)!")
            case 18..<23: return String(localized: "Buonasera\(name)!")
            default: return String(localized: "Ancora sveglio\(name)?")
            }
        case .name:
            return firstName.map { String(localized: "Ciao, \($0)") } ?? String(localized: "Ciao!")
        case .motto:
            let mottos = [
                String(localized: "Un passo alla volta."),
                String(localized: "Oggi conta."),
                String(localized: "Pausa caffè meritata."),
                String(localized: "Tutto pronto?"),
                String(localized: "Si parte!"),
                String(localized: "Piano piano, ma senza fermarsi."),
                String(localized: "Anche questa è fatta."),
            ]
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day) ?? 0
            return mottos[dayOfYear % mottos.count]
        case .week:
            let week = calendar.component(.weekOfYear, from: day)
            let weekday = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7 + 1
            return String(localized: "Settimana \(week) · giorno \(weekday) di 7")
        }
    }
}

/// How the day and date are laid out.
nonisolated enum DateLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// "15.09" over "MAR".
    case stacked
    /// "MAR 15 SET" on one line.
    case inline
    /// A huge day number, weekday and month beside it.
    case bigDay
    /// "Martedì" over "15 settembre", in words.
    case words
    /// The weekday alone, large.
    case weekday

    /// The layout's identity, which is its raw value.
    var id: String { rawValue }

    /// What the layout is called in Personalizza.
    var title: LocalizedStringKey {
        switch self {
        case .stacked: "Impilata"
        case .inline: "In linea"
        case .bigDay: "Giorno grande"
        case .words: "A parole"
        case .weekday: "Solo giorno"
        }
    }
}

/// Which edge the date and greeting sit against.
nonisolated enum DateAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Against the leading edge, centred, or against the trailing edge.
    case leading, center, trailing
    /// The alignment's identity, which is its raw value.
    var id: String { rawValue }

    /// The SF Symbol shown in the picker.
    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    /// The alignment as a stack takes it.
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// The alignment as a frame takes it.
    var frame: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// The alignment as multi-line text takes it.
    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// The date in the chosen layout, font and colour.
struct DateHeader: View {
    /// The day to write.
    let day: Date
    /// The look, which supplies the layout, typeface, weight, colour and alignment.
    let style: TodayStyle
    /// The size of the largest line; previews in the editor pass a smaller one.
    var size: CGFloat = 72

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        content
            .foregroundStyle(style.dateTint(scheme))
            .multilineTextAlignment(style.dateAlignment.text)
            .frame(maxWidth: .infinity, alignment: style.dateAlignment.frame)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.interpolate)
    }

    /// The look's date typeface at a share of the header's size.
    ///
    /// - Parameter scale: The size as a fraction of ``size``.
    /// - Returns: The font.
    private func font(_ scale: CGFloat) -> Font {
        style.dateFont.font(size: size * scale, weight: style.dateWeight)
    }

    /// The date written out in whichever layout the look asks for.
    @ViewBuilder
    private var content: some View {
        switch style.dateLayout {
        case .stacked:
            VStack(alignment: style.dateAlignment.horizontal, spacing: -size * 0.25) {
                Text(day.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale))
                    .replacingOccurrences(of: "/", with: "."))
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased())
            }
            .font(font(1))
        case .inline:
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)).uppercased())
                .font(font(0.5))
        case .bigDay:
            HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
                Text(day.formatted(.dateTime.day().locale(locale)))
                    .font(font(1.6))
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized)
                    Text(day.formatted(.dateTime.month(.wide).locale(locale)).capitalized)
                        .opacity(0.6)
                }
                .font(font(0.3))
            }
        case .words:
            VStack(alignment: style.dateAlignment.horizontal, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.wide).locale(locale)).capitalized)
                    .font(font(0.62))
                Text(day.formatted(.dateTime.day().month(.wide).locale(locale)))
                    .font(font(0.36))
                    .opacity(0.7)
            }
        case .weekday:
            Text(day.formatted(.dateTime.weekday(.wide).locale(locale)).uppercased())
                .font(font(0.68))
        }
    }
}
