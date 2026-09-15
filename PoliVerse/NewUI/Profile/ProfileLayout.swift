import SwiftUI

/// How the top of the profile is laid out, chosen from its ••• menu.
enum ProfileLayout: String, CaseIterable, Identifiable {
    /// Photo in the middle, name and course under it.
    case classic
    /// A student card, the kind you would show at a library desk.
    case card
    /// A coloured cover with the photo overlapping its lower edge.
    case banner
    /// Photo beside the name, and the key numbers straight away.
    case dashboard

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classico"
        case .card: "Tessera"
        case .banner: "Copertina"
        case .dashboard: "Cruscotto"
        }
    }

    var systemImage: String {
        switch self {
        case .classic: "person.crop.circle"
        case .card: "person.text.rectangle"
        case .banner: "photo.artframe"
        case .dashboard: "gauge.with.dots.needle.33percent"
        }
    }

    static let storageKey = "profileLayout"
}

extension ProfileSummary.Badge {
    var title: LocalizedStringKey {
        switch self {
        case .firstExam: "Primo esame"
        case .fiveExams: "Cinque esami"
        case .tenExams: "Dieci esami"
        case .firstThirty: "Primo 30"
        case .honours: "Lode"
        case .fiftyCredits: "50 CFU"
        case .halfway: "Metà strada"
        case .highAverage: "Media da 27"
        case .allPassedThisYear: "Anno completo"
        }
    }

    var systemImage: String {
        switch self {
        case .firstExam: "checkmark.seal.fill"
        case .fiveExams: "5.circle.fill"
        case .tenExams: "10.circle.fill"
        case .firstThirty: "star.fill"
        case .honours: "crown.fill"
        case .fiftyCredits: "square.stack.3d.up.fill"
        case .halfway: "flag.checkered"
        case .highAverage: "chart.line.uptrend.xyaxis"
        case .allPassedThisYear: "calendar.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .firstExam: .green
        case .fiveExams, .tenExams: .blue
        case .firstThirty: .orange
        case .honours: .yellow
        case .fiftyCredits: .teal
        case .halfway: .indigo
        case .highAverage: .pink
        case .allPassedThisYear: .mint
        }
    }
}
