import SwiftUI

/// The course tile on Home.
///
/// Keeps the shape language of the 2023 prototype — a large rounded card with a
/// tinted corner motif — but every value is bound to a ``Course`` instead of
/// hardcoded, and the corner art is drawn with a gradient rather than shipping
/// megabytes of stock photography.
struct CourseCard: View {
    let course: Course
    let onOpen: () -> Void
    let onFavourite: () -> Void
    let onMaterials: () -> Void
    var onHide: () -> Void = {}

    private var accent: Color { Theme.accent(for: course) }

    /// Icon buttons grow with the user's text size instead of staying 34pt.
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 34

    @ViewBuilder
    private var cfuChip: some View {
        if course.cfu > 0 {
            Label("\(course.cfu) CFU", systemImage: "graduationcap")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(0.15), in: .capsule)
                .foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onMaterials) {
            Image(systemName: "folder.fill")
                .frame(width: controlSize, height: controlSize)
        }
        .buttonStyle(.plain)
        .background(Color(.tertiarySystemFill), in: .circle)
        .accessibilityLabel("Materiali di \(course.name)")

        Menu {
            Button(course.isFavourite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                   systemImage: course.isFavourite ? "star.slash" : "star",
                   action: onFavourite)
            Button("Apri materiali", systemImage: "folder", action: onMaterials)
            Divider()
            // Mirrors WeBeep's own "Rimuovi dalla vista": the course stays
            // enrolled, it just stops crowding the list.
            Button("Rimuovi dalla vista", systemImage: "eye.slash", action: onHide)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: controlSize, height: controlSize)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .accessibilityLabel("Altre azioni")

        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("Apri")
                Image(systemName: "arrow.up.right")
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .background(accent, in: .capsule)
        .foregroundStyle(Theme.onAccent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.teacher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(course.name)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if course.isFavourite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Preferito")
                }
            }

            Spacer(minLength: 12)

            // At accessibility text sizes the chip and the "Apri" label grow
            // enough that a single row overflows — the CFU chip started
            // wrapping mid-word. Fall back to stacking rather than squeezing.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    cfuChip
                    Spacer(minLength: 4)
                    actionButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    cfuChip
                    HStack(spacing: 8) {
                        actionButtons
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .topTrailing) {
                    // The corner motif: cheap, resolution-independent, themed.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.35), accent.opacity(0)],
                                center: .center, startRadius: 0, endRadius: 130
                            )
                        )
                        .frame(width: 220, height: 220)
                        .offset(x: 70, y: -90)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CourseCard(course: MockData.courses[0], onOpen: {}, onFavourite: {}, onMaterials: {})
        .padding()
}
