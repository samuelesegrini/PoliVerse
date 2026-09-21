#if DEBUG
import SwiftUI

/// What MetricKit has delivered to this phone, for whoever is debugging it.
///
/// Debug builds only, and English only on purpose: it is a developer's tool,
/// so its strings stay out of the String Catalog. Each report can be shared
/// as its JSON — to a Mac, where `atos` turns its addresses into symbols.
struct MetricReportsView: View {
    @State private var entries: [ReportArchive.Entry] = []

    var body: some View {
        List {
            Section {
                if entries.isEmpty {
                    Text(verbatim: "No reports yet. In Xcode: Debug → Simulate MetricKit Payloads.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    ShareLink(item: entry.url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.url.deletingPathExtension().lastPathComponent)
                                .font(.caption.monospaced())
                            Text(verbatim: "\(entry.kind.rawValue) · \(entry.bytes.formatted(.byteCount(style: .file))) · \(entry.date.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(verbatim: "Kept on this device only, newest first, capped at 60 files.")
            }
            .lookRow()

            if !entries.isEmpty {
                Button(role: .destructive) {
                    Task {
                        await ReportArchive.shared.removeAll()
                        await reload()
                    }
                } label: {
                    Text(verbatim: "Delete all reports")
                }
            }
        }
        .lookList()
        .navigationTitle(Text(verbatim: "MetricKit"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        entries = await ReportArchive.shared.entries()
    }
}

#Preview {
    MetricReportsView().previewInNavigation()
}
#endif
