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

    /// The view's content.
    @ViewBuilder
    var body: some View {
        if let section = look.section(kind) {
            if kind.forms.count > 1 {
                GlassSegmentedPicker("Forma", selection: binding(section.form) { $0.form = $1 }, options: kind.forms) { form in
                    Label(form.title, systemImage: form.systemImage).labelStyle(.titleOnly)
                }
                .accessibilityIdentifier("section-form")
            }
            if kind.listsItems {
                Stepper(value: binding(section.itemLimit) { $0.itemLimit = $1 }, in: TodaySection.itemLimits) {
                    Text("Elementi: \(section.itemLimit)")
                }
            }
            Toggle("Compatta", isOn: binding(section.density == .compact) { $0.density = $1 ? .compact : .comfortable })
            Toggle("Nel colore della data", isOn: binding(section.tinted) { $0.tinted = $1 })
            if kind.hasCourseColours, section.form == .list {
                Toggle("Colori dei corsi", isOn: binding(section.courseColours) { $0.courseColours = $1 })
            }
            Picker("Superficie", selection: binding(section.material) { $0.material = $1 }) {
                Text("Come le altre").tag(TodayMaterial?.none)
                ForEach(TodayMaterial.allCases) { material in
                    Text(material.title).tag(Optional(material))
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// A binding to one of the section's settings, animating its change.
    private func binding<Value>(_ value: Value, _ set: @escaping (inout TodaySection, Value) -> Void) -> Binding<Value> {
        Binding {
            value
        } set: { new in
            withAnimation(.snappy) { look.updateSection(kind) { set(&$0, new) } }
        }
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
