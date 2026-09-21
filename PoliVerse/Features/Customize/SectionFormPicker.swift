import SwiftUI

/// A section's page in Personalizza, in the shape of adding a widget: one card
/// of the page per form, swiped through at full size, then turned over for the
/// surface controls.
///
/// The card is a slice of the real page — its background, its Flavor, the
/// section drawn by ``TodaySectionView`` — so what is chosen is what appears.
/// Turning it over keeps it one object: the controls belong to that card, not
/// to a screen somewhere else.
struct SectionFormPicker: View {
    let kind: TodaySection.Kind
    @Binding var style: TodayStyle
    /// Back to the bento, once the section is off the page.
    var close: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.shell) private var shell
    @State private var page: TodaySection.Form
    @State private var flipped = false

    init(kind: TodaySection.Kind, style: Binding<TodayStyle>, close: @escaping () -> Void = {}) {
        self.kind = kind
        _style = style
        self.close = close
        // Set before the first layout, so a section already in another form
        // does not open on the list and jump.
        _page = State(initialValue: style.wrappedValue.section(kind)?.form ?? .list)
    }

    private static let turn = Animation.spring(duration: 0.45, bounce: 0.12)

    private var forms: [TodaySection.Form] { kind.forms }

    private var section: TodaySection {
        style.section(kind) ?? TodaySection(kind: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !flipped, forms.count > 1 {
                header
            }

            card
                .padding(.horizontal, 20)
                .padding(.top, flipped ? 8 : 18)

            Spacer(minLength: 12)

            if flipped {
                Button("Fine", systemImage: "checkmark") { withAnimation(Self.turn) { flipped = false } }
                    .buttonStyle(FlavorGlossButtonStyle(flavor: style.flavor))
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("form-done")
            } else {
                footer
            }
        }
        .padding(.bottom, 18)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        // Swiping to a card is choosing it: the page behind follows at once,
        // the way the gallery's carousel works.
        .onChange(of: page) { _, form in
            guard section.form != form else { return }
            withAnimation(.snappy) { style.updateSection(kind) { $0.form = form } }
        }
    }

    // MARK: - Front

    private var header: some View {
        VStack(spacing: 5) {
            Text("Forma")
                .font(.largeTitle.weight(.bold))
            Text("Come sono disposti gli elementi. Puoi cambiarla quando vuoi.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 6)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                withAnimation(Self.turn) { flipped = true }
            } label: {
                Label("Superficie e contenuto", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FlavorGlossButtonStyle(flavor: style.flavor))
            .padding(.horizontal, 20)
            .accessibilityIdentifier("form-use")
        }
    }

    // MARK: - The card, and its back

    private var card: some View {
        ZStack {
            front
                .opacity(flipped ? 0 : 1)
                .accessibilityHidden(flipped)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
                .accessibilityHidden(!flipped)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }

    private var front: some View {
        TabView(selection: $page) {
            ForEach(forms) { form in
                SectionPageCard(kind: kind, form: form, style: style, day: shell.day)
                    .padding(.bottom, 2)
                    .tag(form)
                    .accessibilityIdentifier("form-\(form.rawValue)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 340)
        .overlay(alignment: .bottom) {
            if forms.count > 1 {
                FormStepper(forms: forms, page: page, style: style)
                    .padding(.bottom, -44)
            }
        }
        .padding(.bottom, forms.count > 1 ? 44 : 0)
    }

    private var back: some View {
        SectionControlsCard(kind: kind, style: $style, onFlip: { withAnimation(Self.turn) { flipped = false } },
                            onHide: {
                                style.hideSection(kind)
                                close()
                            })
            .frame(height: 340)
    }
}

// MARK: - The forms as a control

/// The forms under the card: which one is on screen, and how many there are.
///
/// The name over its dots, as it was — the card above is the thing to look at
/// and this only has to be read. What it gained: the name is in the look's own
/// typeface and changes with the card instead of snapping, and the dot for the
/// form on screen stretches into the Flavor's accent, so the colour says which
/// one it is as much as the position does.
private struct FormStepper: View {
    let forms: [TodaySection.Form]
    let page: TodaySection.Form
    let style: TodayStyle

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = style.accent(scheme)
        VStack(spacing: 9) {
            Text(page.title)
                .font(.subheadline.weight(.semibold))
                .fontDesign(style.textDesign.design)
                .lineLimit(1)
                // Keyed by form, so one name leaves as the next arrives rather
                // than the glyphs changing under the reader.
                .id(page)
                .transition(.blurReplace)
            HStack(spacing: 6) {
                ForEach(forms) { form in
                    Capsule()
                        .fill(form == page ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                        .frame(width: form == page ? 16 : 6, height: 6)
                }
            }
        }
        // The card is swiped, not this: it follows whichever one comes to rest.
        .animation(.snappy(duration: 0.3), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Forma"))
        .accessibilityValue(Text(page.title))
    }
}

// MARK: - The page as a card

/// One form drawn as a slice of the page: the background, the section, and the
/// top of whatever comes next fading out at the card's edge.
private struct SectionPageCard: View {
    let kind: TodaySection.Kind
    let form: TodaySection.Form
    let style: TodayStyle
    let day: Date

    @Environment(\.colorScheme) private var scheme

    /// The look this card shows: the same one, with this form on the section.
    private var preview: TodayStyle {
        var preview = style
        preview.updateSection(kind) { $0.form = form }
        if preview.section(kind) == nil { preview.sections.append(shownSection) }
        return preview
    }

    private var shownSection: TodaySection {
        var section = style.section(kind) ?? TodaySection(kind: kind)
        section.form = form
        return section
    }

    /// The next section on the page, to say that this is a page and not a
    /// floating card.
    private var following: TodaySection? {
        let visible = style.visibleSections
        guard let index = visible.firstIndex(where: { $0.kind == kind }), index + 1 < visible.count else { return nil }
        return visible[index + 1]
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 12) {
            // The section is what the card is for: it takes the space left
            // over and sits in the middle of it. Stacked from the top it was
            // pushed up by whatever followed, and half of each showed.
            TodaySectionView(section: shownSection, style: preview, day: day)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if let following {
                // A strip of the next section, cut off at a fixed height: it
                // says this is a page rather than a floating card, and cannot
                // grow enough to take the middle back.
                TodaySectionView(section: following, style: preview, day: day)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 62, alignment: .top)
                    .clipped()
                    .opacity(0.5)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.12), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { TodayBackgroundView(style: preview, cornerRadius: 28) }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        // Only a look that fixes an appearance overrides the viewer's.
        .environment(\.colorScheme, preview.appearance.colorScheme ?? scheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(form.title))
    }
}

// MARK: - The back

/// The card's back: what the section is made of and how much it shows.
private struct SectionControlsCard: View {
    let kind: TodaySection.Kind
    @Binding var style: TodayStyle
    var onFlip: () -> Void
    var onHide: () -> Void

    private var section: Binding<TodaySection> {
        Binding {
            style.section(kind) ?? TodaySection(kind: kind)
        } set: { new in
            style.updateSection(kind) { $0 = new }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            materials
            Picker("Densità", selection: section.density) {
                ForEach(TodaySection.Density.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if kind.listsItems {
                Stepper(value: section.itemLimit, in: TodaySection.itemLimits) {
                    Text("Elementi mostrati: \(section.wrappedValue.itemLimit)")
                        .font(.subheadline)
                }
            }
            Toggle("Colore del Flavor", isOn: section.tinted)
                .font(.subheadline)
            // Course colours draw one card per lesson: only the list has them.
            if kind.hasCourseColours, section.wrappedValue.form == .list {
                Toggle("Colori dei corsi", isOn: section.courseColours)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Button("Nascondi dalla pagina", systemImage: "eye.slash", role: .destructive, action: onHide)
                    .font(.subheadline)
                    .accessibilityIdentifier("form-hide")
                Text("Una sezione nascosta tiene le sue impostazioni.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background { TodayBackgroundView(style: style, cornerRadius: 28) }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button("Gira la scheda", systemImage: "arrow.trianglehead.2.clockwise.rotate.90", action: onFlip)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.7), in: .circle)
                .padding(12)
                .accessibilityIdentifier("form-flip-back")
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }

    /// The materials as swatches, the page's own first.
    private var materials: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Superficie")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    swatch(nil, title: "Come la pagina")
                    ForEach(TodayMaterial.allCases) { material in
                        swatch(material, title: material.title)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func swatch(_ material: TodayMaterial?, title: LocalizedStringKey) -> some View {
        let chosen = section.wrappedValue.material == material
        return Button {
            withAnimation(.snappy) { style.updateSection(kind) { $0.material = material } }
        } label: {
            VStack(spacing: 5) {
                MaterialPreview(material: material ?? style.material, style: style)
                    .frame(width: 62, height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
                    }
                Text(title)
                    .font(.caption2.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("section-material-\(material?.rawValue ?? "page")")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

#Preview("Forma") {
    @Previewable @State var style = TodayStyle()
    NavigationStack {
        SectionFormPicker(kind: .upcoming, style: $style)
    }
    .previewEnvironment()
}
