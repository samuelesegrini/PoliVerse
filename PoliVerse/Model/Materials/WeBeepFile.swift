import Foundation

/// A file published on WeBeep, the Politecnico's Moodle instance.
nonisolated struct WeBeepFile: Identifiable, Sendable, Hashable, Codable {
    /// The file's identity within its course, built from its module, folder and name.
    let id: String
    /// The file's name, extension included.
    let name: String
    /// The ``Course/id`` this file belongs to.
    let courseID: String
    /// The course section it was published in.
    let sectionName: String
    /// The file's size in bytes.
    let sizeBytes: Int
    /// When the file last changed on WeBeep.
    let modifiedAt: Date
    /// Where to fetch the file, with the Moodle token already appended. `nil` when Moodle
    /// gave no address.
    let downloadURL: URL?
    /// Whether a copy is already on the device.
    var isDownloaded: Bool = false

    /// The file's extension, lower-cased. Empty when it has none.
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    /// The SF Symbol for the file's kind, chosen from ``fileExtension``.
    var icon: String {
        switch fileExtension {
        case "pdf": "doc.richtext"
        case "zip", "rar", "7z": "doc.zipper"
        case "mp4", "mov", "mkv": "play.rectangle"
        case "ppt", "pptx": "rectangle.on.rectangle"
        case "doc", "docx": "doc.text"
        case "xls", "xlsx", "csv": "tablecells"
        case "png", "jpg", "jpeg", "heic": "photo"
        default: "doc"
        }
    }

    /// ``sizeBytes`` formatted for display.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

/// A section of a course's WeBeep page — “Lezione 1”, “Materiale d'esame” — and the
/// files in it.
nonisolated struct WeBeepSection: Identifiable, Sendable, Hashable, Codable {
    /// The section's identity within its course.
    let id: String
    /// The section's name, as the course page shows it.
    let name: String
    /// The files published in the section.
    let files: [WeBeepFile]
}
