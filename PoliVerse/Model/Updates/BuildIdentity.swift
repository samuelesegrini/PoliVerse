import Foundation

/// Build provenance is stamped by the local build script, never inferred from receipt files.
nonisolated struct BuildIdentity {
    let commit: String?
    let channel: String

    init(bundle: Bundle = .main) {
        let raw = bundle.object(forInfoDictionaryKey: "PoliVerseBuildCommit") as? String ?? ""
        commit = raw.count == 40 && raw.allSatisfy { $0.isHexDigit } ? raw : nil
        let track = bundle.object(forInfoDictionaryKey: "PoliVerseBuildChannel") as? String ?? ""
        #if DEBUG
        channel = track == "local" ? "Build locale" : "Sviluppo"
        #else
        channel = track == "local" ? "Build locale" : "Standard"
        #endif
    }
    var commitURL: URL? {
        commit.flatMap { URL(string: "https://github.com/samuelesegrini/PoliVerse/commit/" + $0) }
    }
}
