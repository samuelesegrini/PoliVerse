import Foundation

/// A file published on WeBeep (the Moodle instance at `webeep.polimi.it`).
nonisolated struct WeBeepFile: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let courseID: String
    let sectionName: String
    let sizeBytes: Int
    let modifiedAt: Date
    let downloadURL: URL?
    var isDownloaded: Bool = false

    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

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

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

/// A WeBeep course section ("Lezione 1", "Materiale d'esame", …).
nonisolated struct WeBeepSection: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let files: [WeBeepFile]
}
