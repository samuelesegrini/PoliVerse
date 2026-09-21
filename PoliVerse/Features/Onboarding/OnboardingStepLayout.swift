import SwiftUI

/// The one colour the first run draws with.
///
/// ``Theme/brand`` resolves to the `AccentColor` asset, while every button on
/// these screens resolves to the environment tint that ``lookControls()`` sets
/// from the look. In light mode the two happen to be the same navy and nobody
/// notices; in dark they are two different blues, side by side — the progress
/// bar and the symbols in one, the buttons in the other, on the same screen.
///
/// So the flow reads the look's control colour directly, exactly as the
/// buttons do, and there is one accent again.
@MainActor
struct OnboardingTint: DynamicProperty {
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    var color: Color { style.controlTint(scheme) }
    /// The same colour as components, for the tiles that build a ramp on it.
    var rgb: Flavor.RGB { style.controlAccent(dark: scheme == .dark) }
}

/// The shape every step after the welcome shares: a symbol, a title, a
/// paragraph that says why the step exists, the step's own content, and the
/// buttons pinned at the bottom where the thumb is.
///
/// One layout rather than five, so the steps differ in what they ask and not
/// in where their buttons sit.
struct OnboardingStepLayout<Content: View, Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    private var tint = OnboardingTint()
    /// Scaled, matching the hero tiles in Impostazioni (``HeroTileStack``).
    @ScaledMetric(relativeTo: .largeTitle) private var iconSide: CGFloat = 88

    /// Whether the step's content is taller than the room it has.
    ///
    /// At the default text size most of these steps fit, and a bar drawn under
    /// the buttons over empty space is a line that separates nothing. At the
    /// accessibility sizes they all overflow, and then the words run under the
    /// buttons and end mid-sentence against them — so the bar appears exactly
    /// when there is something behind it to cut off.
    @State private var overflows = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    // The same tile Impostazioni draws its hero pictures and a
                    // course's icon with, not a bare symbol: every full-screen
                    // icon in the app is drawn this way.
                    GlassTile(symbol: symbol, colour: tint.rgb, side: iconSide, surface: .glass)
                        .padding(.top, 28)

                    Text(title)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.center)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    content
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            // Nothing to bounce against on the short steps.
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.containerSize.height + 1
            } action: { _, isOverflowing in
                overflows = isOverflowing
            }

            VStack(spacing: 12) { actions }
                .padding(.horizontal, 28)
                .padding(.top, overflows ? 14 : 0)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    if overflows {
                        Rectangle()
                            .fill(.bar)
                            .overlay(alignment: .top) { Divider() }
                            .ignoresSafeArea(edges: .bottom)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: overflows)
        }
    }
}

/// One line of "what this means", with its own symbol.
struct OnboardingPoint: View {
    let symbol: String
    let text: LocalizedStringKey

    private var tint = OnboardingTint()

    init(symbol: String, text: LocalizedStringKey) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint.color)
                .frame(width: 22)
        }
    }
}

/// The button that ends a step without doing what it offered. Every step past
/// the sign-in has one: a setup that cannot be postponed is a wall.
struct OnboardingSkipButton: View {
    var title: LocalizedStringKey = "Più tardi"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("onboarding-skip")
    }
}

/// The filled button that carries the step's actual offer.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    /// Something the tap started is still running. The button keeps its size
    /// and its place — a row that collapses to a spinner makes the screen jump
    /// at the exact moment the student is waiting to see whether it worked.
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).font(.headline)
                    .opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isBusy)
        .accessibilityIdentifier("onboarding-primary")
    }
}
