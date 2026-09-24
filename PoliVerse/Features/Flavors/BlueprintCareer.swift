import SwiftUI

/// What expires, in Blueprint: one box per deadline, the days left or the mark
/// in a cell of its own, the most urgent in the mark colour.
struct BlueprintDeadlines: View {
    /// The deadlines, most urgent first.
    let deadlines: [CareerDeadline]
    /// Opens a sitting's own screen.
    let open: (ExamSession) -> Void

    /// The look in use.
    @Environment(\.look) private var style
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        if !deadlines.isEmpty {
            let palette = BlueprintPalette(style)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(deadlines.prefix(3).enumerated()), id: \.element.id) { index, deadline in
                    BlueprintBox(label: "\(["A", "B", "C"][index]) · \(kicker(deadline))") {
                        HStack(alignment: .center, spacing: 14) {
                            stub(deadline)
                                .foregroundStyle(index == 0 ? palette.mark : palette.ink)
                                .frame(minWidth: 64)
                            Rectangle().frame(width: 1).opacity(0.55).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(deadline.exam.courseName.uppercased())
                                    .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                                    .lineLimit(2)
                                if let line = line(deadline) {
                                    Text(line).font(.blueprint(11, relativeTo: .caption1)).opacity(0.72)
                                }
                                Button { open(deadline.exam) } label: {
                                    Text(deadline.kind == .refusableGrade ? "VEDI L’ESITO" : "VEDI L’APPELLO")
                                        .font(.blueprint(12, bold: true, relativeTo: .caption1))
                                        .tracking(1)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 36)
                                        .foregroundStyle(index == 0 ? palette.paper : palette.ink)
                                        .background(index == 0 ? palette.ink : .clear)
                                        .overlay { Rectangle().strokeBorder(.white, lineWidth: 1.5) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The days left, or the mark still to decide.
    @ViewBuilder
    private func stub(_ deadline: CareerDeadline) -> some View {
        if deadline.kind == .refusableGrade {
            Text(deadline.exam.grade?.display ?? "—")
                .font(.blueprint(30, bold: true, relativeTo: .largeTitle))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else {
            let days = max(deadline.days(from: .now) ?? 0, 0)
            VStack(spacing: 0) {
                Text("\(days)").font(.blueprint(34, bold: true, relativeTo: .largeTitle))
                Text(days == 1 ? "GIORNO" : "GIORNI").font(.blueprint(10, relativeTo: .caption2)).tracking(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// What the box is.
    private func kicker(_ deadline: CareerDeadline) -> String {
        switch deadline.kind {
        case .enrolmentClosing: String(localized: "ISCRIZIONI")
        case .refusableGrade: String(localized: "VOTO")
        case .sitting: String(localized: "ESAME")
        }
    }

    /// When, in a line.
    private func line(_ deadline: CareerDeadline) -> String? {
        let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)
        switch deadline.kind {
        case .enrolmentClosing:
            return deadline.at.map { String(localized: "chiudono \($0.formatted(day))") }
        case .refusableGrade:
            return String(localized: "rifiutabile dai Servizi Online")
        case .sitting:
            guard let at = deadline.at else { return nil }
            return [at.formatted(day.hour().minute()), deadline.exam.room?.lowercased()].compactMap { $0 }
                .joined(separator: " · ")
        }
    }
}

/// Where the student stands, in Blueprint: the average marked on a scale from
/// 18 to 30, the credits as a dimension line, the graduation base beside.
struct BlueprintStanding: View {
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

    /// The view's content.
    var body: some View {
        let palette = BlueprintPalette(style)
        BlueprintBox(label: String(localized: "D · MEDIA")) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—")
                        .font(.blueprint(48, bold: true, relativeTo: .largeTitle))
                    if let delta, delta != 0 {
                        Text(delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))
                            .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                            .foregroundStyle(palette.mark)
                    }
                    Spacer(minLength: 0)
                    if mean > 0 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text((mean * 110 / 30).formatted(.number.precision(.fractionLength(1))))
                                .font(.blueprint(20, bold: true, relativeTo: .title3))
                            Text("/ 110 · BASE").font(.blueprint(10, relativeTo: .caption2)).opacity(0.72)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                scale(palette)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CREDITI").font(.blueprint(10, relativeTo: .caption2)).tracking(1.4).opacity(0.72)
                    GeometryReader { proxy in
                        let share = book.plannedCFU > 0 ? min(CGFloat(book.earnedCFU) / CGFloat(book.plannedCFU), 1) : 0
                        ZStack(alignment: .leading) {
                            Rectangle().frame(height: 1).opacity(0.4)
                            Rectangle().frame(width: proxy.size.width * share, height: 3)
                            Rectangle().frame(width: 1, height: 12).offset(x: proxy.size.width * share - 0.5)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 14)
                    .accessibilityHidden(true)
                    Text("\(book.earnedCFU) / \(book.plannedCFU) CFU")
                        .font(.blueprint(12, bold: true, relativeTo: .caption1))
                }
                .accessibilityElement(children: .combine)
                Button(action: simulate) {
                    Text("SIMULA LA MEDIA")
                        .font(.blueprint(14, bold: true, relativeTo: .subheadline))
                        .tracking(1)
                        .foregroundStyle(palette.paper)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The scale from 18 to 30 with a tick per mark and the average marked on it.
    private func scale(_ palette: BlueprintPalette) -> some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (mark: Double) in CGFloat((mark - 18) / 12) * width }
                ZStack(alignment: .topLeading) {
                    Rectangle().frame(height: 1).offset(y: 10)
                    ForEach(18...30, id: \.self) { mark in
                        Rectangle()
                            .frame(width: 1, height: mark % 3 == 0 ? 12 : 6)
                            .offset(x: x(Double(mark)), y: mark % 3 == 0 ? 4 : 7)
                    }
                    if mean >= 18 {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.mark)
                            .offset(x: x(min(mean, 30)) - 5.5, y: -8)
                    }
                }
            }
            .frame(height: 20)
            HStack {
                ForEach([18, 21, 24, 27, 30], id: \.self) { mark in
                    Text("\(mark)")
                    if mark != 30 { Spacer(minLength: 0) }
                }
            }
            .font(.blueprint(10, relativeTo: .caption2))
            .opacity(0.72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Media su una scala da 18 a 30"))
        .accessibilityValue(Text(mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—"))
    }
}

/// The path to the degree in Blueprint: a dimension line with a mark per year,
/// and the ways into the rest of Carriera as a row of boxes.
struct BlueprintPath: View {
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

    /// The view's content.
    var body: some View {
        let palette = BlueprintPalette(style)
        let years = max(Int((Double(book.plannedCFU) / 60).rounded()), 1)
        let progress = book.plannedCFU > 0 ? min(Double(book.earnedCFU) / Double(book.plannedCFU), 1) : 0
        VStack(alignment: .leading, spacing: 10) {
            BlueprintHeading(title: String(localized: "E · PERCORSO"))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().frame(height: 1).opacity(0.5)
                    Rectangle().fill(palette.mark).frame(width: proxy.size.width * progress, height: 3)
                    ForEach(0...years, id: \.self) { stop in
                        Rectangle()
                            .frame(width: 1.5, height: 14)
                            .offset(x: proxy.size.width * CGFloat(stop) / CGFloat(years) - (stop == years ? 1.5 : 0))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Percorso"))
            .accessibilityValue(Text("\(book.earnedCFU) CFU su \(book.plannedCFU)"))
            HStack {
                ForEach(0...years, id: \.self) { stop in
                    Text(stop == years ? String(localized: "LAUREA") : String(localized: "\(stop + 1)° ANNO"))
                    if stop != years { Spacer(minLength: 0) }
                }
            }
            .font(.blueprint(10, relativeTo: .caption2))
            .opacity(0.8)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                tool("PIANO", action: plan)
                tool("SIMULA", action: simulate)
                tool("NOVITÀ", action: updates)
            }
            .overlay { Rectangle().strokeBorder(.white, lineWidth: 2) }
            .padding(.top, 6)
        }
    }

    /// One way into the rest of Carriera, a cell of the row.
    private func tool(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.blueprint(12, bold: true, relativeTo: .caption1))
                .tracking(1.2)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay { Rectangle().stroke(.white.opacity(0.6), lineWidth: 1) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
