import Foundation
import Observation

/// Experiments are opt-in per install. Availability is enforced here as well as in Settings.
nonisolated enum BetaFeature: String, CaseIterable, Identifiable, Sendable {
    case campus3D

    var id: String { rawValue }
    var storageKey: String { "betaFeature." + rawValue }
    var title: LocalizedStringResource {
        switch self { case .campus3D: "Campus 3D" }
    }
    var detail: LocalizedStringResource {
        switch self {
        case .campus3D: "Esplora il Trifoglio in tre dimensioni. Il modello è ancora incompleto; disattiva l’anteprima per tornare ad Apple Maps."
        }
    }
    var isAvailable: Bool {
        switch self {
        case .campus3D:
            #if DEBUG && os(iOS)
            true
            #else
            false
            #endif
        }
    }
}

@MainActor @Observable
final class FeatureFlags {
    private let defaults: UserDefaults
    private let available: Set<BetaFeature>
    private var enabled: Set<BetaFeature>

    init(defaults: UserDefaults = .standard,
         available: Set<BetaFeature> = Set(BetaFeature.allCases.filter(\.isAvailable))) {
        self.defaults = defaults
        self.available = available
        enabled = Set(BetaFeature.allCases.filter { defaults.bool(forKey: $0.storageKey) })
    }

    var availableFeatures: [BetaFeature] { BetaFeature.allCases.filter { available.contains($0) } }
    func isEnabled(_ feature: BetaFeature) -> Bool {
        available.contains(feature) && enabled.contains(feature)
    }
    func setEnabled(_ value: Bool, for feature: BetaFeature) {
        guard available.contains(feature) else { return }
        if value { enabled.insert(feature) } else { enabled.remove(feature) }
        defaults.set(value, forKey: feature.storageKey)
    }
    func reset() {
        enabled.removeAll()
        for feature in BetaFeature.allCases { defaults.removeObject(forKey: feature.storageKey) }
    }
}
