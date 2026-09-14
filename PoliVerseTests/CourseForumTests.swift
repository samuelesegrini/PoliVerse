import Foundation
import Testing
@testable import PoliVerse

/// The forums a course page offers, so its hub can show Avvisi and Forum
/// next to materials and programme.
@Suite("Course forums")
struct CourseForumTests {
    private let sections = [
        MoodleSection(id: 1, name: "Generale", modules: [
            MoodleModule(id: 1, name: "Forum di discussione", modname: "forum", contents: nil, instance: 11),
            MoodleModule(id: 2, name: "Avvisi", modname: "forum", contents: nil, instance: 12),
            MoodleModule(id: 3, name: "Lezione 1", modname: "resource", contents: nil, instance: 13),
        ]),
        MoodleSection(id: 2, name: "Laboratorio", modules: [
            MoodleModule(id: 4, name: "Domande sul progetto", modname: "forum", contents: nil, instance: 14),
            MoodleModule(id: 5, name: "Senza istanza", modname: "forum", contents: nil),
        ]),
    ]

    @Test("Announcements and discussion forums are told apart, announcements first")
    func kinds() {
        let forums = CourseForum.forums(in: sections)
        #expect(forums.map(\.id) == [12, 11, 14])
        #expect(forums.map(\.kind) == [.announcements, .discussion, .discussion])
    }

    @Test("The detector and the hub agree on which forum is the announcements one")
    func agreesWithDetector() {
        #expect(CourseForum.forums(in: sections).filter { $0.kind == .announcements }.map(\.id)
            == AnnouncementDetector.forumInstances(in: sections))
    }

    @Test("A discussion's posts decode, replies after the opening post")
    func posts() throws {
        let json = """
        {"posts":[
          {"id":2,"discussionid":9,"parentid":1,"hasparent":true,"subject":"Re: Esame","message":"<p>Grazie</p>",
           "timecreated":1772000100,"author":{"fullname":"Mario Rossi"}},
          {"id":1,"discussionid":9,"parentid":null,"hasparent":false,"subject":"Esame","message":"<p>Aula L.26</p>",
           "timecreated":1772000000,"author":{"fullname":"Stefano Ceri"}}
        ],"warnings":[]}
        """
        let decoded = try JSONDecoder().decode(MoodlePosts.self, from: Data(json.utf8))
        let ordered = decoded.chronological
        #expect(ordered.map(\.id) == [1, 2])
        #expect(ordered.first?.author?.fullname == "Stefano Ceri")
        #expect(ordered.last?.isReply == true)
    }
}
