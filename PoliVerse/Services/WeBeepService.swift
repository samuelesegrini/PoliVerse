import Foundation
import Observation
import OSLog

/// Course materials from WeBeep, via Moodle's web services.
///
/// The token is obtained by ``WeBeepAuth``'s launch handshake and kept in the
/// Keychain alongside — but separate from — the PoliMi OAuth token. They are
/// independent credentials with independent lifetimes: the PoliMi session can
/// be alive while the WeBeep one is dead, and vice versa.
@Observable
final class WeBeepService {
    enum State: Equatable {
        case needsLogin
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .needsLogin
    private(set) var courses: [MoodleCourse] = []
    private(set) var sections: [WeBeepSection] = []
    private(set) var isLoadingMaterials = false

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "webeep")
    private let keychainAccount = "webeep"

    private var api: WeBeepAPI?
    private var userID: Int?
    /// Course id per PoliMi course code, learned by matching names once.
    private var courseIDByCode: [String: Int] = [:]

    init(session: Session) {
        self.session = session
        if let token = storedToken() {
            api = WeBeepAPI(token: token)
        }
    }

    var isAuthenticated: Bool { api != nil }

    // MARK: - Token

    private func storedToken() -> String? {
        guard let data = KeychainStore.load(account: keychainAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(_ token: WeBeepAuth.MoodleToken) {
        try? KeychainStore.save(Data(token.token.utf8), account: keychainAccount)
        api = WeBeepAPI(token: token.token)
        state = .ready
    }

    func signOut() {
        KeychainStore.delete(account: keychainAccount)
        api = nil
        userID = nil
        courses = []
        sections = []
        courseIDByCode = [:]
        state = .needsLogin
    }

    // MARK: - Loading

    /// Fetches the enrolled course list, establishing the user id on the way.
    func loadCourses() async {
        if session.useMockData {
            state = .ready
            return
        }
        guard let api else {
            state = .needsLogin
            return
        }

        state = .loading
        do {
            let info = try await api.siteInfo()
            userID = info.userid
            courses = try await api.courses(userID: info.userid)
            state = .ready
        } catch let error as WeBeepAPI.Failure {
            handle(error)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMaterials(for course: Course) async {
        guard !isLoadingMaterials else { return }
        isLoadingMaterials = true
        defer { isLoadingMaterials = false }

        if session.useMockData || api == nil {
            sections = MockData.weBeepSections(for: course)
            if api == nil && !session.useMockData { state = .needsLogin }
            return
        }

        guard let api else { return }

        do {
            if courses.isEmpty { await loadCourses() }
            guard let moodleID = moodleCourseID(for: course) else {
                sections = []
                state = .failed("Corso non trovato su WeBeep.")
                return
            }

            let raw = try await api.contents(courseID: moodleID)
            sections = raw.compactMap { section in
                let files = (section.modules ?? []).flatMap { module in
                    (module.contents ?? []).compactMap { content -> WeBeepFile? in
                        // Modules carry more than files — `url` entries point
                        // offsite, labels carry none at all.
                        guard content.type == "file",
                              let name = content.filename,
                              let fileURL = content.fileurl else { return nil }
                        return WeBeepFile(
                            id: "\(module.id)-\(name)",
                            name: name,
                            courseID: course.id,
                            sectionName: section.name,
                            sizeBytes: content.filesize ?? 0,
                            modifiedAt: content.timemodified.map {
                                Date(timeIntervalSince1970: TimeInterval($0))
                            } ?? .now,
                            downloadURL: api.authenticatedFileURL(fileURL)
                        )
                    }
                }
                guard !files.isEmpty else { return nil }
                return WeBeepSection(id: String(section.id), name: section.name, files: files)
            }
            state = .ready
        } catch let error as WeBeepAPI.Failure {
            handle(error)
            sections = []
        } catch {
            state = .failed(error.localizedDescription)
            sections = []
        }
    }

    /// Matches a PoliMi course to its Moodle counterpart.
    ///
    /// The two systems share no identifier — Moodle has its own numeric course
    /// id and a free-text `fullname`, while PoliMi uses `c_insegn_piano`. The
    /// course code often appears inside the Moodle title (WeBeep names courses
    /// like "097785 - BASI DI DATI"), so try that first and fall back to
    /// comparing normalised names.
    private func moodleCourseID(for course: Course) -> Int? {
        // A course sourced from WeBeep already knows its Moodle id; no matching
        // required, and no chance of matching wrongly.
        if let direct = course.moodleID { return direct }
        if let cached = courseIDByCode[course.id] { return cached }

        if let byCode = courses.first(where: {
            $0.fullname.contains(course.id) || ($0.shortname ?? "").contains(course.id)
        }) {
            courseIDByCode[course.id] = byCode.id
            return byCode.id
        }

        let target = course.name.lowercased()
        if let byName = courses.first(where: {
            let full = Course.normalise($0.fullname).lowercased()
            return full.contains(target) || target.contains(full)
        }) {
            courseIDByCode[course.id] = byName.id
            return byName.id
        }

        log.warning("No WeBeep course matched \(course.id) \(course.name)")
        return nil
    }

    private func handle(_ error: WeBeepAPI.Failure) {
        if error.isAuthFailure {
            // The token is dead; drop it so the UI offers login rather than
            // retrying against a credential that will never work again.
            signOut()
        } else {
            state = .failed(error.localizedDescription)
        }
    }
}
