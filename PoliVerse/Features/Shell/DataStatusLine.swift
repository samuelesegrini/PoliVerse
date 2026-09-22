import SwiftUI

/// What the screen is showing, said once, at the bottom of it.
///
/// The predecessor was a yellow banner pinned under the navigation bar that
/// only ever said one thing — "dati di esempio" — and said it in the one place
/// where it covered the buttons it sat over. This says all of ``DataStatus``'s
/// states in the same voice and the same spot, and, like Photos' iCloud line,
/// it is **not there at all** when there is nothing to report: no reserved
/// height, no placeholder.
///
/// A tap opens Impostazioni, where the detail lives.
struct DataStatusLine: View {
    /// False in the current interface, which has no Impostazioni sheet to
    /// open: there the line reports and nothing more, rather than offering a
    /// tap that would do nothing.
    var opensSettings = true

    /// The shared ``DataStatus``, from the environment.
    @Environment(DataStatus.self) private var status
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// The view's content.
    var body: some View {
        if !status.isQuiet {
            HStack(spacing: 7) {
                Image(systemName: status.symbol)
                    .symbolRenderingMode(.hierarchical)
                    // The one state that is actively working: spin it, so a
                    // slow pass reads as progress rather than as a stuck line.
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: status.state == .refreshing)
                Text(status.summary)
                if status.state == .sample {
                    Button("Esci") { session.useMockData = false }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brand)
                }
            }
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(0.18)))
            .padding(.bottom, 6)
            .contentShape(.capsule)
            .onTapGesture {
                guard opensSettings else { return }
                shell.present { shell.showingSettings = true }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.snappy(duration: 0.28), value: status.state)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(status.summary))
            .accessibilityHint(opensSettings ? "Apre Impostazioni" : "")
            .accessibilityIdentifier("data-status")
        }
    }

    /// Orange for the two states someone has to do something about, secondary
    /// for the two that resolve themselves.
    private var tint: Color {
        switch status.state {
        case .sample, .failed: .orange
        case .offline, .refreshing, .updated, .idle: .secondary
        }
    }
}

/// A system symbol with a badge in its corner, built the way SF Symbols builds
/// `gear.badge.checkmark`.
///
/// Apple's badged symbols do not simply stack a dot on top of the glyph: the
/// base symbol is **cut away** behind the badge, leaving an even gap all the
/// way round, so the badge reads as a separate object rather than as a blob
/// stuck to the artwork. That notch is what this reproduces — a circle punched
/// out of the symbol with `destinationOut`, the badge drawn into the hole —
/// because over the bar's glass an opaque ring would show as a pale halo
/// instead of letting the material through.
///
/// It exists because the badged cogs in SF Symbols are all drawn on `gear`,
/// the classic cog, and this app's settings button is `gearshape` everywhere.
/// A button that changed cog when something went wrong would read as a
/// different button rather than as the same one with news.
struct BadgedSymbol: View {
    /// The mark in the cog's notch: a dot, or a glyph, in a colour that says how urgent it is.
    struct Badge: Equatable {
        /// The mark inside the badge. Nil is a plain dot: enough to be
        /// noticed, for a state that is not an error.
        var glyph: String?
        /// The badge's colour.
        var tint: Color
    }

    /// The SF Symbol to draw, notch and all.
    let symbol: String
    /// The badge to punch into it, or `nil` for the plain symbol.
    let badge: Badge?

    /// The symbol's nominal point size. Scaled, so the badge keeps its
    /// proportions and its distance from the cog when the reader turns text
    /// up — the one thing a hand-placed overlay usually gets wrong.
    @ScaledMetric(relativeTo: .body) private var pointSize: CGFloat = 17

    /// Proportions taken from `gear.badge.checkmark`: the badge is a little
    /// under two thirds of the symbol's box, the gap around it a tenth. It
    /// sits at the bottom trailing corner, where it is clear of the bar's
    /// glass edge and of the neighbouring profile button.
    private var diameter: CGFloat { pointSize * 0.58 }
    /// The clear ring between the badge and the symbol, a tenth of the symbol's box.
    private var gap: CGFloat { pointSize * 0.08 }

    /// The view's content.
    var body: some View {
        Image(systemName: symbol)
            .overlay(alignment: .bottomTrailing) {
                if badge != nil {
                    // The notch: the badge's circle plus the gap, removed from
                    // the symbol underneath.
                    Circle()
                        .frame(width: diameter + gap * 2, height: diameter + gap * 2)
                        .blendMode(.destinationOut)
                        .offset(x: gap, y: gap)
                }
            }
            // Ends the layer the punch applies to: without it the hole would
            // be cut through everything behind the button as well.
            .compositingGroup()
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Circle()
                        .fill(badge.tint)
                        .frame(width: diameter, height: diameter)
                        .overlay {
                            if let glyph = badge.glyph {
                                Image(systemName: glyph)
                                    .font(.system(size: diameter * 0.58, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .offset(x: gap, y: gap)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }
}

/// Impostazioni in the bar, carrying a mark when the data behind it needs
/// attention.
struct SettingsBarButton: View {
    /// The shared ``DataStatus``, from the environment.
    @Environment(DataStatus.self) private var status
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// The failure gets the cross, sample data the bare dot. The line at the
    /// bottom of the screen says which; this only has to be noticed.
    private var badge: BadgedSymbol.Badge? {
        switch status.badge {
        case .attention: BadgedSymbol.Badge(glyph: "xmark", tint: .orange)
        case .sample: BadgedSymbol.Badge(glyph: nil, tint: .orange)
        case nil: nil
        }
    }

    /// The view's content.
    var body: some View {
        Button { shell.present { shell.showingSettings = true } } label: {
            BadgedSymbol(symbol: "gearshape", badge: badge)
                .animation(.snappy(duration: 0.3), value: status.badge)
        }
        .accessibilityLabel(status.badge == nil
                            ? Text("Impostazioni")
                            : Text("Impostazioni, \(String(localized: status.summary))"))
        .accessibilityIdentifier("bar-settings")
    }
}

/// Putting the status line at the bottom of a screen.
extension View {
    /// The status line above whatever is at the bottom of the screen. Draws
    /// nothing, and takes no height, while there is nothing to say.
    func dataStatusLine(opensSettings: Bool = true) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { DataStatusLine(opensSettings: opensSettings) }
    }
}

// MARK: - Previews

#Preview("Dati di esempio") {
    NavigationStack {
        Color.clear.dataStatusLine().toolbar {
            ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }
        }
    }
    .previewEnvironment()
}
