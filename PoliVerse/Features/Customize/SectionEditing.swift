import SwiftUI

extension TodaySection {
    /// What the section is set to, in a line: its form, how many entries, how
    /// dense, its own surface.
    var summary: Text {
        var parts = [Text(form.title)]
        if kind.listsItems { parts.append(Text("\(itemLimit) elementi")) }
        if density == .compact { parts.append(Text("compatta")) }
        if let material { parts.append(Text(material.title)) }
        return parts.dropFirst().reduce(parts[0]) { line, part in Text("\(line) · \(part)") }
    }
}

/// One section's settings: its form, how many entries, density, its own
/// surface, whether it takes the date's colour, and for the timetable the
/// courses' colours.
struct SectionSettings: View {
    /// Which section.
    let kind: TodaySection.Kind
    /// The look being edited.
    @Binding var look: TodayStyle

    var showsForm = true

    private var section: TodaySection { look.section(kind) ?? TodaySection(kind: kind) }
    private func binding<Value>(_ path: WritableKeyPath<TodaySection, Value>) -> Binding<Value> {
        Binding { (look.section(kind) ?? TodaySection(kind: kind))[keyPath: path] }
            set: { value in withAnimation(.snappy) { look.updateSection(kind) { $0[keyPath: path] = value } } }
    }

    var body: some View {
        if look.section(kind) != nil {
            if showsForm, kind.forms.count > 1 {
                GlassSegmentedPicker("Forma", selection: binding(\.form), options: kind.forms) {
                    Label($0.title, systemImage: $0.systemImage).labelStyle(.titleOnly)
                }
                .accessibilityIdentifier("section-form")
            }
            materials
            GlassSegmentedPicker("Densità", selection: binding(\.density)) { Text($0.title) }
            if kind.listsItems {
                Stepper(value: binding(\.itemLimit), in: TodaySection.itemLimits) {
                    Text("Elementi mostrati: \(section.itemLimit)")
                }
            }
            Toggle("Nel tuo colore", isOn: binding(\.tinted))
            if kind.hasCourseColours, section.form == .list {
                Toggle("Colori dei corsi", isOn: binding(\.courseColours))
            }
        }
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

    /// One material as a small preview, ringed when chosen.
    ///
    /// - Parameters:
    ///   - material: The material, or `nil` to follow the page's.
    ///   - title: What it is called.
    /// - Returns: The swatch.
    private func swatch(_ material: TodayMaterial?, title: LocalizedStringKey) -> some View {
        let chosen = section.material == material
        return Button {
            withAnimation(.snappy) { look.updateSection(kind) { $0.material = material } }
        } label: {
            VStack(spacing: 5) {
                MaterialPreview(material: material ?? look.material, style: look)
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

/// The sections' task on iPhone, docked under the page zoomed onto its cards:
/// the sections on the page in their order, − to take one off and ≡ to move
/// it, a tap for its settings; then the ones not on the page, + to add.
struct SectionTaskDock: View {
    /// The look being edited.
    @Binding var look: TodayStyle

    /// The section whose settings are open, if any.
    @State private var detail: TodaySection.Kind?

    /// The view's content.
    var body: some View {
        Group {
            if let detail, look.section(detail).map({ !$0.isHidden }) ?? false {
                settings(detail)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: detail)
    }

    /// The sections on the page, then the rest.
    private var list: some View {
        List {
            Section {
                ForEach(look.visibleSections) { section in
                    Button { detail = section.kind } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.kind.systemImage)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.kind.title)
                                section.summary
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("section-task-\(section.kind.rawValue)")
                    // The page needs at least one section.
                    .deleteDisabled(look.visibleSections.count <= 1)
                }
                .onMove { offsets, destination in
                    let visible = look.visibleSections
                    let moved = offsets.map { visible[$0].kind }
                    let target = destination < visible.count ? visible[destination].kind : nil
                    withAnimation(.snappy) { look.moveSections(moved, before: target) }
                }
                .onDelete { offsets in
                    let visible = look.visibleSections
                    withAnimation(.snappy) { offsets.map { visible[$0].kind }.forEach { look.hideSection($0) } }
                }
            } header: {
                Text("Sulla pagina")
            } footer: {
                Text("Trascina ≡ per riordinare. Tocca una sezione per le sue opzioni.")
            }
            if !look.addableSections.isEmpty {
                Section("Aggiungi") {
                    ForEach(look.addableSections) { kind in
                        Button {
                            withAnimation(.snappy) { look.addSection(kind) }
                        } label: {
                            Label {
                                Text(kind.title)
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .accessibilityIdentifier("section-task-add-\(kind.rawValue)")
                    }
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .scrollContentBackground(.hidden)
    }

    /// One section's settings, with the way back to the list.
    private func settings(_ kind: TodaySection.Kind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    detail = nil
                } label: {
                    Label("Sezioni", systemImage: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("section-task-back")
                Spacer()
                Text(kind.title).font(.headline)
                Spacer()
                // Balances the back button, so the title sits in the middle.
                Label("Sezioni", systemImage: "chevron.left").hidden()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Form {
                SectionSettings(kind: kind, look: $look)
                Section {
                    Button("Nascondi la sezione", role: .destructive) {
                        withAnimation(.snappy) { look.hideSection(kind) }
                        detail = nil
                    }
                    .disabled(look.visibleSections.count <= 1)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
