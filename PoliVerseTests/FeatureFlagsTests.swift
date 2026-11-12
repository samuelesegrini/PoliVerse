import Foundation
import Testing
@testable import PoliVerse

@Suite("Funzioni in anteprima") @MainActor
struct FeatureFlagsTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "FeatureFlagsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("Una nuova installazione non attiva anteprime")
    func optIn() {
        withDefaults { defaults in
            let flags = FeatureFlags(defaults: defaults, available: [.campus3D])
            #expect(!flags.isEnabled(.campus3D))
            flags.setEnabled(true, for: .campus3D)
            #expect(flags.isEnabled(.campus3D))
            #expect(FeatureFlags(defaults: defaults, available: [.campus3D]).isEnabled(.campus3D))
            flags.setEnabled(false, for: .campus3D)
            #expect(!FeatureFlags(defaults: defaults, available: [.campus3D]).isEnabled(.campus3D))
        }
    }

    @Test("Un valore salvato non supera i limiti della build")
    func availabilityWins() {
        withDefaults { defaults in
            defaults.set(true, forKey: BetaFeature.campus3D.storageKey)
            let flags = FeatureFlags(defaults: defaults, available: [])
            #expect(!flags.isEnabled(.campus3D))
            #expect(flags.availableFeatures.isEmpty)
            flags.setEnabled(true, for: .campus3D)
            #expect(!flags.isEnabled(.campus3D))
        }
    }

    @Test("Il campus di notte si sceglie a parte dal Campus 3D")
    func darkCampusIsSeparate() {
        withDefaults { defaults in
            let flags = FeatureFlags(defaults: defaults, available: [.campus3D, .campus3DDark])
            flags.setEnabled(true, for: .campus3D)
            #expect(!flags.isEnabled(.campus3DDark))
            flags.setEnabled(true, for: .campus3DDark)
            #expect(flags.isEnabled(.campus3DDark))
            flags.reset()
            #expect(!flags.isEnabled(.campus3D) && !flags.isEnabled(.campus3DDark))
        }
    }

    @Test("Il ripristino cancella anche le anteprime non disponibili")
    func reset() {
        withDefaults { defaults in
            defaults.set(true, forKey: BetaFeature.campus3D.storageKey)
            FeatureFlags(defaults: defaults, available: []).reset()
            #expect(!FeatureFlags(defaults: defaults, available: [.campus3D]).isEnabled(.campus3D))
            #expect(defaults.object(forKey: BetaFeature.campus3D.storageKey) == nil)
        }
    }
}
