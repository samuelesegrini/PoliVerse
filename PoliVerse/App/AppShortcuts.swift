import AppIntents

/// The phrases Siri accepts. Each needs `.applicationName` somewhere in it,
/// so they read as "… in PoliVerse" rather than competing with every other
/// app's "apri l'orario".
struct PoliVerseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTimetableIntent(),
            phrases: ["Apri l'orario in \(.applicationName)",
                      "Lezioni di oggi in \(.applicationName)"],
            shortTitle: "Orario",
            systemImageName: "calendar")
        AppShortcut(
            intent: OpenFreeRoomsIntent(),
            phrases: ["Trova un'aula libera in \(.applicationName)",
                      "Aule libere in \(.applicationName)"],
            shortTitle: "Aule libere",
            systemImageName: "building.2")
        AppShortcut(
            intent: OpenCareerIntent(),
            phrases: ["Apri la carriera in \(.applicationName)",
                      "La mia media in \(.applicationName)"],
            shortTitle: "Carriera",
            systemImageName: "chart.bar")
        AppShortcut(
            intent: ExamUpdatesIntent(),
            phrases: ["Novità sui miei esami in \(.applicationName)",
                      "Ci sono esiti nuovi in \(.applicationName)"],
            shortTitle: "Novità esami",
            systemImageName: "bell.badge")
        AppShortcut(
            intent: NextExamIntent(),
            phrases: ["Quando è il prossimo esame in \(.applicationName)",
                      "Prossimo esame in \(.applicationName)"],
            shortTitle: "Prossimo esame",
            systemImageName: "calendar.badge.clock")
        AppShortcut(
            intent: OpenMaterialsIntent(),
            phrases: ["Apri WeBeep in \(.applicationName)",
                      "Materiali dei corsi in \(.applicationName)"],
            shortTitle: "WeBeep",
            systemImageName: "books.vertical")
    }
}
