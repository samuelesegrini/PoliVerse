import SwiftUI

/// Drawn copies of Oggi's navigation bar and the tab bar, for Personalizza's
/// cards.
///
/// Each card is the app at full size, so the card of the look in use can grow
/// to cover the screen and back without anything changing at either end: same
/// controls, same glass, same places as the system's bars.
struct ReplicaNavigationBar: View {
    /// Whose avatar the bar shows.
    let student: Student?
    /// The day named in the middle of the bar.
    let day: Date
    /// Which of the bar's controls the look asks for.
    var bar = TodayBarStyle()
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        HStack(spacing: 12) {
            if bar.showsProfile {
                ProfileAvatar(student: student, size: 34)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: .circle)
            }
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
            Spacer(minLength: 0)
            Image(systemName: "calendar")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
            Image(systemName: "paintbrush")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
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
    /// The lesson the accessory is about.
    let current: CurrentClass

    /// The view's content.
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

/// The tab bar as the app draws it: whole, or minimised to the selected tab
/// the way it shrinks while a page scrolls.
struct ReplicaTabBar: View {
    /// Which tab is drawn as chosen: 0 Oggi, 1 Corsi, 2 Carriera.
    var selected = 0
    /// Drawn minimised: the selected tab alone, and search.
    var minimized = false

    /// The bar's tabs, in order.
    private static let tabs: [(title: LocalizedStringKey, icon: String)] = [
        ("Oggi", "calendar.day.timeline.left"), ("Corsi", "books.vertical"), ("Carriera", "graduationcap"),
    ]

    /// The view's content.
    var body: some View {
        HStack(spacing: 10) {
            if minimized {
                Image(systemName: Self.tabs[selected].icon)
                    .symbolVariant(.fill)
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .circle)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 0) {
                    ForEach(Self.tabs.indices, id: \.self) { index in
                        tab(Self.tabs[index].title, Self.tabs[index].icon, selected: index == selected)
                    }
                }
                .padding(4)
                .frame(height: 62)
                .glassEffect(.regular, in: .capsule)
            }

            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .frame(width: minimized ? 52 : 62, height: minimized ? 52 : 62)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, 21)
        .animation(.snappy, value: minimized)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One tab of the bar.
    ///
    /// - Parameters:
    ///   - title: The tab's name.
    ///   - icon: Its SF Symbol.
    ///   - selected: True for the tab drawn as chosen.
    /// - Returns: The tab.
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
