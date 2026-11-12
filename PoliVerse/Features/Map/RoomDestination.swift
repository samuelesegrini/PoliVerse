import SwiftUI

/// Where tapping a room leads: the new map with the room lit when that preview is on and the
/// room's building is modelled in 3D, its detail page otherwise.
struct RoomDestination: View {
    /// The room.
    let room: Classroom
    /// Opt-in preview features for this install.
    @Environment(FeatureFlags.self) private var flags

    /// The view's content.
    var body: some View {
        #if DEBUG && os(iOS)
        if flags.isEnabled(.newMap), CampusMapScreen.canShow(room) {
            CampusMapScreen(target: room)
        } else {
            ClassroomDetailView(room: room)
        }
        #else
        ClassroomDetailView(room: room)
        #endif
    }
}
