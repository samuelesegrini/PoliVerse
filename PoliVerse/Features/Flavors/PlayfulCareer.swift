import SwiftUI

/// What expires, in Giocherelloso: each deadline a ticket whose stub counts
/// the days left, or holds the mark that can still be refused. Nothing at all
/// when nothing expires, as ``CareerNowCard``.
struct PlayfulTickets: View {
    /// The deadlines, most urgent first.
    let deadlines: [CareerDeadline]
    /// Opens a sitting's own screen.
    let open: (ExamSession) -> Void

    /// The look in use.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        if !deadlines.isEmpty {
            let palette = PlayfulPalette(style, scheme: scheme)
            VStack(alignment: .leading, spacing: 10) {
                PlayfulHeading("Cosa scade")
                ForEach(Array(deadlines.prefix(3).enumerated()), id: \.element.id) { index, deadline in
                    ticket(deadline, urgent: index == 0, palette: palette)
                        .playfulLean(index + 1, in: style)
                }
            }
        }
    }

    /// One deadline as a ticket.
    private func ticket(_ deadline: CareerDeadline, urgent: Bool, palette: PlayfulPalette) -> some View {
        PlayfulTicket(stubFill: urgent ? palette.second : palette.secondWash, stubWidth: 84) {
            stub(deadline)
                .foregroundStyle(urgent ? palette.onSecond : palette.secondText)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    PlayfulKicker(text: kicker(deadline), colour: palette.secondText)
                    Text(deadline.exam.courseName)
                        .font(.headline)
                        .lineLimit(2)
                    if let line = line(deadline) {
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { open(deadline.exam) } label: {
                    Text(deadline.kind == .enrolmentClosing ? "Vedi l’appello" : deadline.kind == .refusableGrade
                         ? "Vedi l’esito" : "Vedi l’appello")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .foregroundStyle(urgent ? palette.onMain : Color.primary)
                        .background(urgent ? palette.main : Color.primary.opacity(0.08), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The stub: the days left, or the mark.
    @ViewBuilder
    private func stub(_ deadline: CareerDeadline) -> some View {
        if deadline.kind == .refusableGrade {
            Text(deadline.exam.grade?.display ?? "—")
                .font(.custom("Didot-Bold", size: 36, relativeTo: .largeTitle))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 6)
        } else {
            let days = max(deadline.days(from: .now) ?? 0, 0)
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.playful(44, relativeTo: .largeTitle))
                    .monospacedDigit()
                Text(days == 1 ? "GIORNO" : "GIORNI")
                    .font(.playful(11, relativeTo: .caption2))
                    .tracking(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The small label over the course's name.
    private func kicker(_ deadline: CareerDeadline) -> String {
        switch deadline.kind {
        case .enrolmentClosing: String(localized: "ISCRIZIONI IN CHIUSURA")
        case .refusableGrade: String(localized: "VOTO DA DECIDERE")
        case .sitting: String(localized: "ESAME IN ARRIVO")
        }
    }

    /// When, in a line.
    private func line(_ deadline: CareerDeadline) -> String? {
        let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)
        switch deadline.kind {
        case .enrolmentClosing:
            guard let closes = deadline.at else { return nil }
            let sitting = deadline.exam.date.map { String(localized: " · appello \($0.formatted(day))") } ?? ""
            return String(localized: "Chiudono \(closes.formatted(day))") + sitting
        case .refusableGrade:
            return String(localized: "Puoi ancora rifiutarlo, dai Servizi Online")
        case .sitting:
            guard let at = deadline.at else { return nil }
            return [at.formatted(day.hour().minute()), deadline.exam.room].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// Where the student stands, in Giocherelloso: the credits as a ring in the
/// page's colour, the average set in Didot inside it, the graduation base beside.
struct PlayfulStanding: View {
    /// The career's figures.
    let book: GradeBook
    /// The average, the service's or the libretto's own.
    let mean: Double
    /// How the average moved with the last mark.
    let delta: Double?
    /// Opens the grade simulator.
    let simulate: () -> Void

    /// The look in use.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The ring's size, scaled with the reader's text.
    @ScaledMetric(relativeTo: .largeTitle) private var ring: CGFloat = 128

    /// The view's content.
    var body: some View {
        let palette = PlayfulPalette(style, scheme: scheme)
        let progress = book.plannedCFU > 0 ? min(Double(book.earnedCFU) / Double(book.plannedCFU), 1) : 0
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { dial(progress, palette: palette); figures(palette) }
                VStack(alignment: .leading, spacing: 14) { dial(progress, palette: palette); figures(palette) }
            }
            Button(action: simulate) {
                Label("Simula la media", systemImage: "function")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(palette.onSecond)
                    .background(palette.second, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(palette.onMain)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.main, in: .rect(cornerRadius: 28, style: .continuous))
        .shadow(color: palette.main.opacity(0.3), radius: 16, y: 8)
    }

    /// The credits ring with the average inside.
    private func dial(_ progress: Double, palette: PlayfulPalette) -> some View {
        ZStack {
            Circle().stroke(palette.onMain.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(palette.second, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—")
                    .font(.custom("Didot-Bold", size: 36, relativeTo: .largeTitle))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                PlayfulKicker(text: String(localized: "MEDIA"), colour: palette.onMain.opacity(0.75))
            }
            .padding(14)
        }
        .frame(width: ring, height: ring)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Media"))
        .accessibilityValue(Text(mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—"))
    }

    /// Credits and the graduation base, big.
    private func figures(_ palette: PlayfulPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("\(book.earnedCFU)").font(.playful(28, relativeTo: .title))
                 + Text(" / \(book.plannedCFU) CFU").font(.playful(15, relativeTo: .subheadline)))
                if book.plannedCFU > 0 {
                    Text("il \(Double(book.earnedCFU) / Double(book.plannedCFU), format: .percent.precision(.fractionLength(0))) del percorso")
                        .font(.caption)
                        .opacity(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            if mean > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    (Text((mean * 110 / 30).formatted(.number.precision(.fractionLength(1))))
                        .font(.playful(28, relativeTo: .title))
                     + Text(" / 110").font(.playful(15, relativeTo: .subheadline)))
                    HStack(spacing: 4) {
                        Text("base di laurea")
                        if let delta, delta != 0 {
                            Text(delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))
                                .fontWeight(.bold)
                        }
                    }
                    .font(.caption)
                    .opacity(0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The path from the first year to the degree: a line with a stop per year,
/// filled as far as the credits reach, and the ways into the rest of Carriera.
struct PlayfulPath: View {
    /// The career's figures.
    let book: GradeBook
    /// Opens the study plan.
    let plan: () -> Void
    /// Opens the grade simulator.
    let simulate: () -> Void
    /// Opens the exam news.
    let updates: () -> Void

    /// The look in use.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        let palette = PlayfulPalette(style, scheme: scheme)
        // Sixty credits a year, as the Politecnico counts them.
        let years = max(Int((Double(book.plannedCFU) / 60).rounded()), 1)
        let progress = book.plannedCFU > 0 ? min(Double(book.earnedCFU) / Double(book.plannedCFU), 1) : 0
        let current = min(book.earnedCFU / 60, years - 1)
        VStack(alignment: .leading, spacing: 12) {
            PlayfulHeading("Il tuo percorso")
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12)).frame(height: 6)
                        Capsule().fill(palette.second).frame(width: proxy.size.width * progress, height: 6)
                        HStack {
                            ForEach(0...years, id: \.self) { stop in
                                Circle()
                                    .fill(stop == years ? Color.primary : stop == current ? Color.white : Color(.systemBackground))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        Circle().strokeBorder(stop <= current ? palette.second : Color.primary.opacity(0.2),
                                                              lineWidth: 5)
                                    }
                                if stop != years { Spacer(minLength: 0) }
                            }
                        }
                    }
                    .frame(height: 24)
                }
                .frame(height: 24)
                HStack {
                    ForEach(0...years, id: \.self) { stop in
                        Text(stop == years ? String(localized: "Laurea") : String(localized: "\(stop + 1)° anno"))
                            .font(.playful(12, relativeTo: .caption))
                            .foregroundStyle(stop == current || stop == years ? .primary : .secondary)
                        if stop != years { Spacer(minLength: 0) }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Percorso"))
            .accessibilityValue(Text("\(current + 1)° anno di \(years), \(book.earnedCFU) CFU su \(book.plannedCFU)"))

            HStack(spacing: 8) {
                tool("Piano", symbol: "list.bullet.rectangle", action: plan)
                tool("Simula", symbol: "function", action: simulate)
                tool("Novità", symbol: "bell.badge", action: updates)
            }
        }
    }

    /// One way into the rest of Carriera.
    private func tool(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .todayMaterial(style.material, flavor: style.flavor, mode: style.appearance.flavorMode, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
