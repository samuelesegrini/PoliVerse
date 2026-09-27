import SwiftUI

/// "Dove studi": the degree course and approved plan (PSPA) the app found from the
/// career, to confirm or change, and the campus Aule libere opens on.
///
/// Right after the account, since the plan is read from it: every course page, the
/// syllabus and the personal timetable are read against this plan, and a wrong
/// guess found a month later is a month of wrong pages. With the sample data there
/// is no plan, so only the campus is asked.
struct JourneyStudies: View {
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``RoomsModel``, from the environment.
    @Environment(RoomsModel.self) private var rooms
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var freeRooms
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The campus Aule libere opens on.
    @AppStorage(FavouriteCampus.storageKey) private var favourite = ""
    /// Moves the journey on.
    let advance: () -> Void

    /// Whether the plan picker is up.
    @State private var choosingPlan = false

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            JourneyTitle(resource: "Dove _studi_")
                .padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !session.useMockData {
                        planSection
                    }
                    campusSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 16)
            JourneyAction(title: "Continua", action: finish)
        }
        .task {
            await rooms.load()
            if !rooms.sites.contains(favourite), let biggest = rooms.biggestSite { favourite = biggest }
        }
        .task { await programmes.prepare() }
        .sheet(isPresented: $choosingPlan) { StudyProgrammeSheet() }
    }

    // MARK: - Plan

    /// The plan the app found, or the way to choose one.
    @ViewBuilder
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Corso di studi e piano")
            if let programme = programmes.programme {
                JourneyCard(title: Text(programme.degreeLabel),
                            detail: Text(programme.planLabel)) {
                    avatar
                }
                .accessibilityIdentifier("onboarding-programme")
                JourneyLink(title: "Non è il mio piano: scegli", action: { choosingPlan = true })
                    .accessibilityIdentifier("onboarding-programme-change")
            } else if programmes.isLocating {
                JourneyCard(title: Text("Cerco il tuo piano…"),
                            detail: Text("Dal libretto e dal Manifesto degli studi")) {
                    ProgressView().frame(width: 46, height: 46)
                }
            } else {
                JourneyPill(isOn: false, indicator: .plusMinus, action: { choosingPlan = true }) {
                    avatar
                } label: {
                    Text("Scegli corso e piano")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("onboarding-programme-choose")
            }
            JourneyNote(text: "Il piano approvato (PSPA) decide le schede dei corsi, il syllabus e l’orario personalizzato.")
        }
    }

    /// The plan's avatar: a cap, in the average's gold.
    private var avatar: some View {
        JourneyAvatar(mark: .symbol("graduationcap.fill"),
                      colours: JourneyFlow.Intent.average.colours, side: 46)
    }

    // MARK: - Campus

    /// One pill per site, the favourite ticked.
    @ViewBuilder
    private var campusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("La tua sede")
            if rooms.sites.isEmpty {
                JourneyCard(title: Text("Carico le sedi…"), detail: Text("Per le aule libere")) {
                    ProgressView().frame(width: 46, height: 46)
                }
            }
            ForEach(rooms.sites, id: \.self) { campus in
                JourneyPill(isOn: favourite == campus, indicator: .check, action: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { favourite = campus }
                }) {
                    JourneyAvatar(mark: .symbol("building.2.fill"),
                                  colours: JourneyFlow.Intent.rooms.colours, side: 46)
                } label: {
                    Text(campus)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("onboarding-campus-\(campus)")
            }
        }
    }

    /// A small heading over a group, in landscape ink.
    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(.white.opacity(0.9))
            .textCase(.uppercase)
    }

    /// Confirms the plan the student saw and kept, points Aule libere at the
    /// campus, and moves on.
    private func finish() {
        if programmes.programme?.isConfirmed == false { programmes.confirm() }
        if let campus = rooms.mainCampus(inSite: favourite) { freeRooms.campus = campus }
        advance()
    }
}
