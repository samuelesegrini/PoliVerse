#if DEBUG
import SwiftUI

/// THROWAWAY: illustrated feature stories on the two existing pre-login pages.
/// -PreviewOnboarding intents (or preview) -PrototypeFeatures Illustrated.
/// The drawings explain actions; topic browsing never changes the home or account.
struct JourneyFeaturesPrototype: View {
    enum Chapter { case day, study }
    let chapter: Chapter
    let advance: () -> Void
    static var isEnabled: Bool { CommandLine.arguments.contains("-PrototypeFeatures") }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topic = 0
    @State private var phase = 0
    @State private var playing = true

    private var story: Story { (chapter == .day ? Story.day : Story.study)[topic] }
    private var topics: [String] { chapter == .day ? ["Lezioni", "Aule", "Appelli"] : ["Materiali", "Registrazioni", "Media"] }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    illustration
                        .frame(height: 310)
                        .dynamicTypeSize(.medium)
                        .scaleEffect(0.86)
                        .frame(height: 270)
                        .accessibilityHidden(true)
                        .overlay(alignment: .topTrailing) {
                            Button { playing.toggle() } label: {
                                Image(systemName: playing ? "pause.circle" : "play.circle")
                                    .font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                            }
                            .journeyVibrant()
                            .accessibilityLabel(playing ? "Ferma l’animazione" : "Riprendi l’animazione")
                        }
                    JourneyTitle(resource: story.title)
                        .id(topic)
                    Text(story.explanation)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .journeyVibrant()
                        .frame(maxWidth: 350)
                    HStack(spacing: 4) {
                        ForEach(Array(topics.enumerated()), id: \.offset) { index, name in
                            Button {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { topic = index }
                            } label: {
                                Text(name)
                                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(topic == index ? JourneyInk.cream.opacity(0.8) : .clear, in: .capsule)
                            }
                            .buttonStyle(JourneyPress())
                            .accessibilityAddTraits(topic == index ? .isSelected : [])
                        }
                    }
                    .foregroundStyle(JourneyInk.ink)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, -24)
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            JourneyAction(title: chapter == .day ? "E dopo la lezione?" : "Collega il tuo Poli", action: advance)
        }
        .onAppear {
            if let i = CommandLine.arguments.firstIndex(of: "-PrototypeTopic"),
               CommandLine.arguments.indices.contains(i + 1), let value = Int(CommandLine.arguments[i + 1]) {
                topic = min(max(value, 0), 2)
            }
        }
        .task(id: "\(topic)-\(playing)") {
            guard playing else { return }
            phase = reduceMotion || CommandLine.arguments.contains("-PrototypeStill") ? 2 : 0
            guard !reduceMotion, !CommandLine.arguments.contains("-PrototypeStill") else { return }
            do {
                try await Task.sleep(for: .seconds(0.8))
                withAnimation(.smooth(duration: 0.8)) { phase = 1 }
                try await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth(duration: 0.8)) { phase = 2 }
                try await Task.sleep(for: .seconds(6))
                withAnimation(.easeOut(duration: 0.25)) { topic = (topic + 1) % 3 }
            } catch { /* Leaving or browsing stops the local story. */ }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch (chapter, topic) {
        case (.day, 0): campus(isRoom: false)
        case (.day, 1): campus(isRoom: true)
        case (.day, _): calendar
        case (.study, 0): folder
        case (.study, 1): recording
        default: average
        }
    }

    /// A little campus with an animated route and a highlighted destination.
    private func campus(isRoom: Bool) -> some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 350
            ZStack {
                CampusDrawing(isRoom: isRoom, phase: phase)
                ZStack {
                    Circle().fill(JourneyInk.action.opacity(0.12)).frame(width: 42, height: 42)
                    Circle().fill(.white).frame(width: 24, height: 24)
                    Circle().fill(JourneyInk.action).frame(width: 16, height: 16)
                }
                .position(x: (phase == 0 ? 74 : 192) * scale, y: phase == 0 ? 244 : 178)
                .opacity(isRoom ? 0 : 1)
                bubble(isRoom ? "Aula 3.1.2" : "Analisi 2", detail: isRoom ? "Libera fino alle 14:00" : "10:15 · Aula B.2.4", symbol: isRoom ? "door.left.hand.open" : "mappin")
                    .rotationEffect(.degrees(-4))
                    .position(x: 176 * scale, y: 55)
                    .opacity(phase > 0 ? 1 : 0)
                    .offset(y: phase > 0 ? 0 : 18)
                if !isRoom {
                    Label("Tra 25 minuti si comincia", systemImage: "bell.badge.fill")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(JourneyInk.ink)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(JourneyInk.cream, in: .capsule)
                        .rotationEffect(.degrees(3))
                        .position(x: 193 * scale, y: 278)
                        .opacity(phase == 2 ? 1 : 0)
                        .offset(y: phase == 2 ? 0 : 12)
                }
            }
        }
    }

    /// The deadline is a calendar page, with its window drawing closed beside it.
    private var calendar: some View {
        ZStack {
            Ellipse().fill(JourneyInk.ink.opacity(0.12)).frame(width: 260, height: 30).offset(y: 119).blur(radius: 9)
            RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.88, green: 0.65, blue: 0.42))
                .frame(width: 225, height: 217).rotationEffect(.degrees(8)).offset(x: 13, y: -2)
            VStack(spacing: 0) {
                Text("FEBBRAIO").font(.system(.caption, design: .rounded, weight: .heavy)).tracking(3)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(JourneyInk.action).foregroundStyle(.white)
                Text("18").font(.system(size: 86, weight: .heavy, design: .rounded)).foregroundStyle(JourneyInk.ink)
                Text("Fisica tecnica").font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(JourneyInk.ink)
                Spacer(minLength: 12)
            }
            .frame(width: 225, height: 217)
            .modifier(IllustratedPaper(radius: 24))
            .clipShape(.rect(cornerRadius: 24)).rotationEffect(.degrees(-7)).offset(y: -14)
            HStack(spacing: 76) {
                Capsule().fill(JourneyInk.ink).frame(width: 7, height: 27)
                Capsule().fill(JourneyInk.ink).frame(width: 7, height: 27)
            }.offset(x: -7, y: -125).rotationEffect(.degrees(-7))
            bubble("Iscrizioni in chiusura", detail: "Domani, alle 23:59", symbol: "bell.fill")
                .rotationEffect(.degrees(3)).offset(x: 10, y: 128)
                .opacity(phase > 0 ? 1 : 0).scaleEffect(phase > 0 ? 1 : 0.9)
            Capsule().fill(JourneyInk.action.opacity(0.65))
                .frame(width: phase == 2 ? 56 : 0, height: 4)
                .rotationEffect(.degrees(-7)).offset(x: -1, y: 20)
        }
    }

    /// Soft edges, a folded lip and paper layers make the folder read as an object.
    private var folder: some View {
        ZStack {
            Ellipse().fill(JourneyInk.ink.opacity(0.15))
                .frame(width: 242, height: 20).blur(radius: 12).offset(y: 135)
            FolderDrawing(front: false)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.69, blue: 0.35), Color(red: 0.79, green: 0.49, blue: 0.21)], startPoint: .top, endPoint: .bottom))
                .overlay { FolderDrawing(front: false).strokeBorderHighlight() }
                .frame(width: 262, height: 172).offset(y: 43)
            paper(title: "ESERCIZI", symbol: "function", tint: Color(red: 0.73, green: 0.36, blue: 0.26))
                .rotationEffect(.degrees(phase > 0 ? 11 : 0))
                .offset(x: phase > 0 ? 57 : 0, y: phase > 0 ? -39 : 28)
            paper(title: "LEZIONE 04", symbol: "doc.text", tint: JourneyInk.action)
                .rotationEffect(.degrees(phase > 0 ? -11 : 0))
                .offset(x: phase > 0 ? -49 : 0, y: phase > 0 ? -57 : 16)
            ZStack {
                FolderDrawing(front: true)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.57), Color(red: 0.96, green: 0.71, blue: 0.36)], startPoint: .topLeading, endPoint: .bottomTrailing))
                FolderDrawing(front: true).strokeBorderHighlight()
                VStack(spacing: 5) {
                    Text("Reti logiche").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("MATERIALI · WEBEEP").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                }
                .foregroundStyle(JourneyInk.ink)
                .padding(.horizontal, 19).padding(.vertical, 12)
                .background(.white.opacity(0.3), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                .offset(y: 11)
                Capsule().fill(Color(red: 0.72, green: 0.46, blue: 0.22).opacity(0.16))
                    .frame(width: 226, height: 2).offset(y: 62)
            }
            .frame(width: 280, height: 146).offset(y: 70)
            .shadow(color: Color(red: 0.47, green: 0.3, blue: 0.13).opacity(0.16), radius: 10, y: 7)
            Image(systemName: "arrow.down")
                .font(.system(size: 21, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 45, height: 45)
                .background(JourneyInk.action.gradient, in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2.5) }
                .shadow(color: JourneyInk.action.opacity(0.22), radius: 7, y: 5)
                .offset(x: 119, y: 123).opacity(phase == 2 ? 1 : 0)
        }
    }

    private var recording: some View {
        ZStack {
            paper(title: "APPUNTI", symbol: "pencil", tint: JourneyInk.inkSoft)
                .rotationEffect(.degrees(15)).offset(x: 87, y: 26)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in Circle().fill(JourneyInk.ink.opacity(0.18)).frame(width: 5, height: 5) }
                    Spacer()
                    Text("Reti logiche · Lezione 4").font(.system(.caption2, design: .rounded, weight: .bold))
                }.foregroundStyle(JourneyInk.inkSoft).padding(12)
                ZStack {
                    Color(red: 0.22, green: 0.35, blue: 0.58)
                    VStack(spacing: 9) {
                        Text("A · B + C").font(.system(size: 32, weight: .medium, design: .serif)).italic()
                        HStack(spacing: 12) {
                            ForEach(0..<3) { i in
                                RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.65), lineWidth: 2).frame(width: 27, height: 20).offset(y: i == 1 ? 8 : 0)
                            }
                        }
                    }.foregroundStyle(.white.opacity(0.9)).offset(y: -14)
                    Image(systemName: "play.fill").font(.system(size: 25, weight: .bold))
                        .foregroundStyle(JourneyInk.action).frame(width: 62, height: 62)
                        .background(JourneyInk.cream, in: .circle).offset(y: 37)
                }.frame(height: 157)
                VStack(spacing: 9) {
                    GeometryReader { proxy in
                        Capsule().fill(JourneyInk.ink.opacity(0.13))
                        Capsule().fill(JourneyInk.action).frame(width: proxy.size.width * (phase > 0 ? 0.39 : 0))
                    }.frame(height: 6)
                    HStack {
                        Text(phase > 0 ? "32:18" : "00:00"); Spacer(); Text("1:24:00")
                    }.font(.system(.caption2, design: .rounded, weight: .bold)).monospacedDigit()
                }.foregroundStyle(JourneyInk.inkSoft).padding(14)
            }
            .frame(width: 270).modifier(IllustratedPaper(radius: 20)).clipShape(.rect(cornerRadius: 20))
            .rotationEffect(.degrees(-5)).offset(x: -13, y: -27)
            .shadow(color: JourneyInk.ink.opacity(0.12), radius: 14, y: 10)
            bubble("Riprendi da 32:18", detail: "Il punto in cui eri rimasto", symbol: "play.fill")
                .rotationEffect(.degrees(3)).offset(x: 14, y: 128)
                .opacity(phase == 2 ? 1 : 0)
        }
    }

    private var average: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.57), Color(red: 0.94, green: 0.7, blue: 0.37)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 263, height: 233).rotationEffect(.degrees(6)).offset(x: 7, y: -11)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LA TUA MEDIA").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.8)
                    Spacer()
                    Image(systemName: "graduationcap.fill").foregroundStyle(JourneyInk.action)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(phase > 0 ? "27,46" : "27,40")
                        .font(.system(size: 43, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText()).monospacedDigit()
                    Text("/ 30").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(JourneyInk.inkSoft)
                }
                ZStack {
                    VStack {
                        ForEach(0..<3) { _ in
                            Rectangle().fill(JourneyInk.ink.opacity(0.07)).frame(height: 1)
                            Spacer(minLength: 0)
                        }
                    }
                    ChartDrawing(progress: phase > 0 ? 1 : 0)
                        .stroke(JourneyInk.action.opacity(0.1), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                        .offset(y: 5)
                    ChartDrawing(progress: phase > 0 ? 1 : 0)
                        .stroke(JourneyInk.action, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    GeometryReader { proxy in
                        Circle().fill(JourneyInk.cream).frame(width: 10, height: 10)
                            .overlay { Circle().strokeBorder(JourneyInk.action, lineWidth: 3) }
                            .position(x: proxy.size.width - 5, y: proxy.size.height * (phase > 0 ? 0.08 : 0.4))
                    }
                }
                .frame(height: 65)
                HStack {
                    Text("Attuale 27,40")
                    Spacer()
                    Text("+0,06 con un 28").foregroundStyle(JourneyInk.action).opacity(phase > 0 ? 1 : 0)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(JourneyInk.ink).padding(21).frame(width: 273)
            .modifier(IllustratedPaper(radius: 24)).rotationEffect(.degrees(-4)).offset(y: -22)
            bubble("E se prendessi 28?", detail: "Simulazione · esame da 8 CFU", symbol: "slider.horizontal.3")
                .rotationEffect(.degrees(3)).offset(x: 11, y: 128)
                .opacity(phase == 2 ? 1 : 0)
        }
    }

    private func bubble(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3.weight(.bold)).foregroundStyle(JourneyInk.action)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .heavy))
                Text(detail).font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(JourneyInk.inkSoft)
            }
        }
        .foregroundStyle(JourneyInk.ink).padding(.horizontal, 16).padding(.vertical, 12)
        .modifier(IllustratedPaper(radius: 20))
    }

    private func paper(title: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                Spacer(minLength: 0)
                Text("PDF").font(.system(size: 8, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(tint.opacity(0.08), in: .rect(cornerRadius: 4))
            }.foregroundStyle(tint)
            Text(title).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5).foregroundStyle(JourneyInk.ink)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4) { i in
                    Capsule().fill(tint.opacity(i == 0 ? 0.25 : 0.13))
                        .frame(width: i == 3 ? 57 : i == 1 ? 84 : 99, height: 3)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Capsule().fill(tint.opacity(0.15)).frame(width: 27, height: 2)
                Spacer()
                Text("04").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(tint.opacity(0.6))
            }
        }
        .padding(17).frame(width: 142, height: 194)
        .modifier(IllustratedPaper(radius: 12))
    }

    private struct Story {
        let title: LocalizedStringResource
        let explanation: String
        static let day = [
            Story(title: "Sai già _dove_\ne quando andare.", explanation: "In Oggi trovi la prossima lezione, l’orario e l’aula. Un promemoria ti avvisa prima che inizi."),
            Story(title: "Un’ora libera?\nTrova anche _l’aula._", explanation: "Scegli il campus e scopri quali aule sono libere, adesso o più tardi. Vedi anche fino a quando puoi fermarti."),
            Story(title: "L’appello si avvicina.\nLa scadenza _si vede._", explanation: "Consulta le date degli appelli e le finestre di iscrizione. Attiva gli avvisi per ricordarti quando chiudono.")
        ]
        static let study = [
            Story(title: "Le slide di WeBeep,\n_dentro il tuo corso._", explanation: "Apri un corso e ritrovi i materiali di WeBeep accanto a orari e registrazioni. Sfoglia le cartelle e apri i documenti."),
            Story(title: "Ti sei perso un pezzo?\n_Riparti da lì._", explanation: "Trova le registrazioni nel corso e riprendi dal punto in cui ti eri fermato. Puoi anche scaricarle per guardarle offline."),
            Story(title: "Prova un voto.\nGuarda la _media._", explanation: "Il libretto raccoglie i tuoi risultati. Prova un voto nella simulazione e guarda come cambia la media, senza modificare gli esami.")
        ]
    }
}

/// The same warm paper and fine light edge across the illustrated objects.
private struct IllustratedPaper: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(colors: [.white, JourneyInk.cream], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            .shadow(color: JourneyInk.ink.opacity(0.06), radius: 2, y: 2)
            .shadow(color: JourneyInk.ink.opacity(0.12), radius: 12, y: 9)
    }
}

private extension Shape {
    func strokeBorderHighlight() -> some View {
        stroke(.white.opacity(0.4), lineWidth: 1)
    }
}

nonisolated private struct FolderDrawing: Shape {
    var front: Bool
    func path(in r: CGRect) -> Path {
        Path { p in
            if front {
                p.move(to: CGPoint(x: 10, y: 12))
                p.addLine(to: CGPoint(x: r.width - 10, y: 0))
                p.addQuadCurve(to: CGPoint(x: r.width, y: 10), control: CGPoint(x: r.width, y: 0))
            } else {
                p.move(to: CGPoint(x: 10, y: 0))
                p.addLine(to: CGPoint(x: 85, y: 0))
                p.addQuadCurve(to: CGPoint(x: 100, y: 8), control: CGPoint(x: 94, y: 0))
                p.addLine(to: CGPoint(x: 111, y: 20))
                p.addLine(to: CGPoint(x: r.width - 10, y: 20))
                p.addQuadCurve(to: CGPoint(x: r.width, y: 30), control: CGPoint(x: r.width, y: 20))
            }
            p.addLine(to: CGPoint(x: r.width - 12, y: r.height - 10))
            p.addQuadCurve(to: CGPoint(x: r.width - 22, y: r.height), control: CGPoint(x: r.width - 13, y: r.height))
            p.addLine(to: CGPoint(x: 22, y: r.height))
            p.addQuadCurve(to: CGPoint(x: 12, y: r.height - 10), control: CGPoint(x: 13, y: r.height))
            p.addLine(to: CGPoint(x: 0, y: front ? 22 : 10))
            p.addQuadCurve(to: CGPoint(x: 10, y: front ? 12 : 0), control: .zero)
            p.closeSubpath()
        }
    }
}

nonisolated private struct ChartDrawing: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: r.height * 0.85))
            p.addLines([CGPoint(x: r.width * 0.18, y: r.height * 0.65), CGPoint(x: r.width * 0.34, y: r.height * 0.73), CGPoint(x: r.width * 0.54, y: r.height * 0.35), CGPoint(x: r.width * 0.72, y: r.height * 0.4), CGPoint(x: r.width, y: r.height * (0.4 - progress * 0.32))])
        }
    }
}

/// A small drawn campus: buildings have walls, roofs, windows, paths and trees.
private struct CampusDrawing: View {
    let isRoom: Bool
    let phase: Int
    var body: some View {
        let ink = JourneyInk.ink
        let cream = JourneyInk.cream
        let action = JourneyInk.action
        return Canvas { context, size in
            let scale = size.width / 350
            context.scaleBy(x: scale, y: 1)
            func polygon(_ points: [CGPoint], _ color: Color) {
                var path = Path(); path.addLines(points); path.closeSubpath(); context.fill(path, with: .color(color))
            }
            func building(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color, lit: Bool) {
                let depth: CGFloat = 22
                context.fill(Path(ellipseIn: CGRect(x: x-3, y: y+height-5, width: width+depth+12, height: 15)), with: .color(ink.opacity(0.12)))
                polygon([CGPoint(x:x,y:y),CGPoint(x:x+width,y:y),CGPoint(x:x+width,y:y+height),CGPoint(x:x,y:y+height)], color)
                polygon([CGPoint(x:x,y:y),CGPoint(x:x+depth,y:y-16),CGPoint(x:x+width+depth,y:y-16),CGPoint(x:x+width,y:y)], color.mix(with: cream, by: 0.2))
                polygon([CGPoint(x:x+width,y:y),CGPoint(x:x+width+depth,y:y-16),CGPoint(x:x+width+depth,y:y+height-16),CGPoint(x:x+width,y:y+height)], color.mix(with: ink, by: 0.18))
                var parapet = Path()
                parapet.addLines([CGPoint(x:x+3,y:y+2),CGPoint(x:x+width-2,y:y+2),CGPoint(x:x+width+depth-2,y:y-13)])
                context.stroke(parapet,with:.color(cream.opacity(0.5)),style:StrokeStyle(lineWidth:1.5,lineCap:.round))
                for row in 0..<2 {
                    for col in 0..<3 {
                        let rect = CGRect(x: x+10+CGFloat(col)*19, y:y+13+CGFloat(row)*20, width:10,height:12)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(lit && row == 0 && col == 1 ? action : cream))
                        if lit && row == 0 && col == 1 {
                            context.stroke(Path(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 4), with: .color(action.opacity(0.35)), lineWidth: 1.5)
                        }
                        context.fill(Path(CGRect(x: rect.minX-1, y: rect.maxY, width: 12, height: 2)),with:.color(ink.opacity(0.13)))
                    }
                }
                context.fill(Path(roundedRect:CGRect(x:x+width/2-7,y:y+height-20,width:14,height:20),cornerRadius:3),with:.color(ink.opacity(0.5)))
            }
            let ground = CGRect(x: 5, y: 122, width: 340, height: 145)
            context.fill(Path(ellipseIn: ground.offsetBy(dx:0,dy:10)),with:.color(ink.opacity(0.1)))
            context.fill(Path(ellipseIn: ground),with:.color(Color(red:0.95,green:0.89,blue:0.73)))
            var walk=Path();walk.move(to:CGPoint(x:45,y:230));walk.addQuadCurve(to:CGPoint(x:286,y:199),control:CGPoint(x:184,y:283))
            context.stroke(walk,with:.color(cream),style:StrokeStyle(lineWidth:22,lineCap:.round))
            building(45, 123, 75, 66, Color(red:0.83,green:0.67,blue:0.49),lit:false)
            building(151, 100, 78, 78, Color(red:0.95,green:0.79,blue:0.52),lit:!isRoom && phase>0)
            building(230, 164, 69, 59, Color(red:0.68,green:0.76,blue:0.62),lit:isRoom && phase>0)
            for (x,y) in [(26.0,185.0),(133,214),(315,180),(206,251),(69,247)] {
                context.fill(Path(ellipseIn:CGRect(x:x-8,y:y+22,width:25,height:7)),with:.color(ink.opacity(0.09)))
                context.fill(Path(roundedRect:CGRect(x:x,y:y,width:5,height:26),cornerRadius:2),with:.color(Color(red:0.52,green:0.4,blue:0.29)))
                context.fill(Path(ellipseIn:CGRect(x:x-11,y:y-21,width:29,height:34)),with:.color(Color(red:0.38,green:0.58,blue:0.37)))
                context.fill(Path(ellipseIn:CGRect(x:x-6,y:y-22,width:19,height:23)),with:.color(Color(red:0.57,green:0.7,blue:0.44)))
            }
            if phase>0 {
                var route=Path();route.move(to:CGPoint(x:74,y:244));route.addCurve(to:CGPoint(x:isRoom ? 265:192,y:isRoom ? 204:174),control1:CGPoint(x:167,y:248),control2:CGPoint(x:198,y:217))
                context.stroke(route,with:.color(action),style:StrokeStyle(lineWidth:4,lineCap:.round,dash:[3,8]))
            }
        }
    }
}
#endif
