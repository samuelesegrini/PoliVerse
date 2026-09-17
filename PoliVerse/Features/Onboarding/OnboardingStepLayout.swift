import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: symbol)
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.brand.gradient)
                        .symbolRenderingMode(.hierarchical)
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

            VStack(spacing: 12) { actions }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
    }
}

/// One line of "what this means", with its own symbol.
struct OnboardingPoint: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.brand)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Theme.brand, in: .capsule)
        .foregroundStyle(Theme.onAccent)
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-primary")
    }
}
