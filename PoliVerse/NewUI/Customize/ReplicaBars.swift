import SwiftUI

/// Drawn copies of Oggi's navigation bar and the tab bar, for Personalizza's
/// cards.
///
/// Each card is the app at full size, so the card of the look in use can grow
/// to cover the screen and back without anything changing at either end: same
/// controls, same glass, same places as the system's bars.
struct ReplicaNavigationBar: View {
    let student: Student?
    let day: Date
    var bar = TodayBarStyle()
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            if bar.showsProfile {
                ProfileAvatar(student: student, size: 34)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            if bar.showsSettings {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22) {
                if bar.showsAdd {
                    Image(systemName: "plus")
                }
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: bar.showsAdd ? 102 : 44, height: 44)
            .glassEffect(.regular, in: bar.showsAdd ? AnyShape(.capsule) : AnyShape(.circle))
        }
        // The date is the bar's principal item: centred on the bar, whatever
        // sits at either side.
        .overlay {
            if bar.showsDate {
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.day().month(.abbreviated).locale(locale)).capitalized)
                        .font(.headline)
                    Image(systemName: "chevron.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The current class above the tab bar, as the tab view's bottom accessory
/// draws it.
struct ReplicaAccessory: View {
    let current: CurrentClass

    var body: some View {
        CurrentClassAccessory(current: current)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 21)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ReplicaTabBar: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                tab("Oggi", "calendar.day.timeline.left", selected: true)
                tab("Corsi", "books.vertical", selected: false)
                tab("Carriera", "graduationcap", selected: false)
            }
            .padding(4)
            .frame(height: 62)
            .glassEffect(.regular, in: .capsule)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 62, height: 62)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, 21)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tab(_ title: LocalizedStringKey, _ icon: String, selected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 20)).symbolVariant(.fill)
            Text(title).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if selected { Capsule().fill(.quaternary.opacity(0.6)) }
        }
    }
}
