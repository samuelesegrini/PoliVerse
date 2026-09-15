import Charts
import SwiftUI

// MARK: - Headers

/// Photo in the middle, name and course under it.
struct ProfileClassicHeader: View {
    let student: Student?
    let summary: ProfileSummary

    var body: some View {
        VStack(spacing: 10) {
            ProfileAvatar(student: student, size: 116)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                .padding(.bottom, 4)
            Text(student?.fullName ?? String(localized: "Ospite"))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            ProfileSubtitle(student: student, summary: summary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// A student card: brand gradient, photo, name, matricola in monospaced
/// digits, and how far the degree has come.
struct StudentIDCard: View {
    let student: Student?
    let summary: ProfileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("POLITECNICO DI MILANO")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .opacity(0.8)
                    Text("Tessera dello studente")
                        .font(.caption)
                        .opacity(0.7)
                }
                Spacer()
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .opacity(0.9)
            }

            HStack(spacing: 14) {
                ProfileAvatar(student: student, size: 64)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(student?.fullName ?? String(localized: "Ospite"))
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if let course = summary.course {
                        Text(course.capitalized)
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(2)
                    }
                }
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matricola").font(.caption2).opacity(0.7)
                    Text(student?.matricola ?? "—")
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(summary.earnedCFU)/\(summary.plannedCFU) CFU")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(value: summary.progress)
                        .tint(.white)
                        .frame(width: 110)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand.mix(with: .blue, by: 0.25), Theme.brand],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 220)
                        .offset(x: 80, y: -90)
                }
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
        }
        .shadow(color: Theme.brand.opacity(0.35), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
    }
}

/// A coloured cover with the photo overlapping its lower edge.
struct ProfileBannerHeader: View {
    let student: Student?
    let summary: ProfileSummary

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.4, 0.55], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Theme.brand, .blue, .indigo,
                    .teal, Theme.brand, .purple,
                    .indigo, .blue, Theme.brand,
                ])
                .frame(height: 150)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))

                ProfileAvatar(student: student, size: 96)
                    .background(Circle().fill(.background).padding(-4))
                    .offset(y: 48)
            }
            .padding(.bottom, 48)

            Text(student?.fullName ?? String(localized: "Ospite"))
                .font(.title2.weight(.bold))
            ProfileSubtitle(student: student, summary: summary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Photo beside the name, then the degree ring and the key numbers.
struct ProfileDashboardHeader: View {
    let student: Student?
    let summary: ProfileSummary

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ProfileAvatar(student: student, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student?.fullName ?? String(localized: "Ospite"))
                        .font(.title3.weight(.bold))
                    ProfileSubtitle(student: student, summary: summary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                DegreeRing(summary: summary)
                    .frame(width: 128, height: 128)
                VStack(spacing: 8) {
                    MiniStat(value: summary.mean.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—",
                             label: "Media", systemImage: "chart.bar.fill", tint: .orange)
                    MiniStat(value: summary.graduationBase.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
                             label: "Base su 110", systemImage: "graduationcap.fill", tint: .indigo)
                }
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

/// Course and year under the name, or the matricola when those are unknown.
private struct ProfileSubtitle: View {
    let student: Student?
    let summary: ProfileSummary

    var body: some View {
        VStack(spacing: 2) {
            if let course = summary.course {
                Text(course.capitalized)
            }
            Text([summary.year.map { String(localized: "\($0)° anno") },
                  student.map { String(localized: "Matricola \($0.matricola)") }]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Numbers

/// Credits earned against the plan, as a ring with the percentage inside.
struct DegreeRing: View {
    let summary: ProfileSummary
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: summary.progress)
                .stroke(AngularGradient(colors: [Theme.brand.mix(with: .teal, by: 0.4), Theme.brand], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(summary.progress, format: .percent.precision(.fractionLength(0)))
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text("\(summary.earnedCFU) CFU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Laurea al \(Int(summary.progress * 100)) per cento, \(summary.earnedCFU) crediti su \(summary.plannedCFU)"))
    }
}

private struct MiniStat: View {
    let value: String
    let label: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The key numbers as a row of tiles.
struct ProfileStatsGrid: View {
    let summary: ProfileSummary

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            tile(summary.mean.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—", "Media", .orange)
            tile("\(summary.earnedCFU)", "CFU", .teal)
            tile("\(summary.passedCount)", "Esami", .green)
            tile(summary.graduationBase.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", "Base su 110", .indigo)
            tile("\(summary.honoursCount)", "Lodi", .yellow)
            tile("\(summary.pendingCount)", "Da fare", .secondary)
        }
    }

    private func tile(_ value: String, _ label: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Every mark in order, with the running mean as a line: whether the
/// average is climbing is what a student wants to see.
struct GradesTrendChart: View {
    let summary: ProfileSummary

    private var running: [(Date, Double)] {
        var points = 0, credits = 0
        return summary.marks.map { mark in
            points += mark.grade * max(mark.cfu, 1)
            credits += max(mark.cfu, 1)
            return (mark.date, Double(points) / Double(credits))
        }
    }

    var body: some View {
        Chart {
            ForEach(summary.marks) { mark in
                BarMark(x: .value("Data", mark.date, unit: .month), yStart: .value("Voto", 18), yEnd: .value("Voto", mark.grade), width: .fixed(8))
                    .foregroundStyle(mark.honours ? AnyShapeStyle(Color.yellow.gradient) : AnyShapeStyle(Theme.brand.opacity(0.35).gradient))
                    .clipShape(Capsule())
            }
            ForEach(running, id: \.0) { date, mean in
                LineMark(x: .value("Data", date, unit: .month), y: .value("Media", mean))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartYScale(domain: 18...31)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(values: [18, 24, 30]) { AxisGridLine(); AxisValueLabel() }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 6)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits), anchor: .top)
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Andamento dei voti")
    }
}

/// The last marks, newest first.
struct RecentGradesList: View {
    let summary: ProfileSummary
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(summary.marks.suffix(4).reversed().enumerated()), id: \.element.id) { index, mark in
                if index > 0 { Divider().padding(.leading, 60) }
                HStack(spacing: 14) {
                    Text(mark.honours ? "30L" : "\(mark.grade)")
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(mark.honours ? .yellow : mark.grade >= 27 ? .green : .primary)
                        .frame(width: 46, height: 46)
                        .background(.quaternary.opacity(0.5), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mark.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text("\(mark.cfu) CFU · \(mark.date.formatted(.dateTime.month(.wide).year().locale(locale)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
    }
}

/// Earned milestones as coloured medals; the rest greyed out.
struct BadgesShelf: View {
    let summary: ProfileSummary

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(ProfileSummary.Badge.allCases) { badge in
                    let earned = summary.badges.contains(badge)
                    VStack(spacing: 8) {
                        Image(systemName: badge.systemImage)
                            .font(.title2)
                            .foregroundStyle(earned ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                            .frame(width: 58, height: 58)
                            .background {
                                Circle().fill(earned ? AnyShapeStyle(badge.color.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)))
                            }
                            .overlay(Circle().strokeBorder(.white.opacity(earned ? 0.4 : 0), lineWidth: 2).padding(3))
                            .shadow(color: earned ? badge.color.opacity(0.35) : .clear, radius: 8, y: 4)
                        Text(badge.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(earned ? .primary : .tertiary)
                            .lineLimit(1)
                    }
                    .frame(width: 74)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(earned ? Text("Ottenuto") : Text("Da ottenere"))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// A titled block on the profile.
struct ProfileSection<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}
