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

    private var accent: Color { Theme.accent(for: course) }

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

            HStack(spacing: 8) {
                if course.cfu > 0 {
                    Label("\(course.cfu) CFU", systemImage: "graduationcap")
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.15), in: .capsule)
                        .foregroundStyle(accent)
                }

                Spacer()

                Button(action: onMaterials) {
                    Image(systemName: "folder.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color(.tertiarySystemFill), in: .circle)
                .accessibilityLabel("Materiali di \(course.name)")

                Menu {
                    Button(course.isFavourite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                           systemImage: course.isFavourite ? "star.slash" : "star",
                           action: onFavourite)
                    Button("Apri materiali", systemImage: "folder", action: onMaterials)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: .circle)
                }
                .accessibilityLabel("Altre azioni")

                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text("Apri")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .background(accent, in: .capsule)
                .foregroundStyle(.white)
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
