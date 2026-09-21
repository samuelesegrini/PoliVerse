import Foundation
import Observation
import OSLog

/// The SPID providers the Politecnico currently federates with, kept from the
/// page rather than from a measurement.
///
/// ``SPIDProvider/all`` is twelve providers read off the live page on
/// 2026-09-12, and that is the right starting point and the wrong long-term
/// answer: the federation changes, and a provider whose `id_idp` moves becomes
/// a button that presses nothing. The login page lists them every single time
/// it loads, so the app reads them while it is there and keeps what it read.
///
/// The list is therefore always **one login behind** — the first login uses the
/// shipped list, refreshes it, and every login after that uses what the page
/// last said. That is the cheapest honest design available: the alternative is
/// a full authorize round trip at launch to fetch a list the student may never
/// need, against a page that sets a session cookie.
///
/// This is the `maps_rest` WADL lesson again, written down in
/// `FreeRoomsModel`: ask the service to describe itself instead of guessing.
@MainActor
@Observable
final class SPIDCatalogue {
    private static let key = "spidProviders"

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "oauth")
    private var stored: [SPIDProvider]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = Self.decode(defaults.string(forKey: Self.key))
    }

    /// What to offer, newest reading first.
    var providers: [SPIDProvider] { stored ?? SPIDProvider.all }

    /// Takes the list the page just reported.
    ///
    /// Anything unreadable is ignored rather than adopted: the page is not ours
    /// and can change shape without warning, and an empty SPID list is a login
    /// method silently disappearing.
    func adopt(_ json: String) {
        guard let parsed = Self.decode(json), !parsed.isEmpty else {
            log.notice("Could not read the SPID list from the page; keeping \(self.providers.count, privacy: .public)")
            return
        }
        guard parsed != stored else { return }
        stored = parsed
        defaults.set(json, forKey: Self.key)
        log.notice("SPID list refreshed from the page: \(parsed.count, privacy: .public) providers")
    }

    private static func decode(_ json: String?) -> [SPIDProvider]? {
        guard let data = json?.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return nil }
        // An entry with no slug cannot be pressed, and one with no id has no
        // fallback either. Either way it is better left out than offered.
        let providers = entries.compactMap(\.provider)
        return providers.isEmpty ? nil : providers
    }

    private struct Entry: Decodable {
        let slug: String
        let identifier: String
        let name: String?

        var provider: SPIDProvider? {
            guard !slug.isEmpty, !identifier.isEmpty else { return nil }
            return SPIDProvider(
                slug: slug,
                identifier: identifier,
                // The page's own accessible label, falling back to the slug:
                // a button named `posteID` is ugly and still usable.
                name: name?.isEmpty == false ? name! : slug)
        }
    }

    /// JavaScript that reads the provider list out of the loaded login page.
    ///
    /// Each provider is an `li` carrying `data-idp`, wrapping a submit button
    /// whose `formaction` holds `id_idp`, and a `.spid-sr-only` span holding
    /// the name screen readers get — which is also the only plain-text name on
    /// the page, the visible one being part of a logo image.
    static let extractionScript = """
    (function () {
      var items = document.querySelectorAll('[data-idp]');
      var out = [];
      for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var slug = item.getAttribute('data-idp') || '';
        var button = item.querySelector('button[formaction]');
        var action = button ? button.getAttribute('formaction') : '';
        var match = /id_idp=(\\d+)/.exec(action || '');
        var label = item.querySelector('.spid-sr-only');
        out.push({
          slug: slug,
          identifier: match ? match[1] : '',
          name: label ? label.textContent.trim() : slug
        });
      }
      return JSON.stringify(out);
    })()
    """
}

/// Which way in the student used last time.
///
/// A student signs in with the same thing every time — their password, or the
/// one SPID provider they actually have — and before this the app made them
/// find it again on every login, SPID behind a button and a list. The
/// remembered method becomes the primary button; the others stay exactly where
/// they were.
@MainActor
@Observable
final class LoginMethodMemory {
    private static let key = "lastLoginMethod"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The method to offer first. The password when there is nothing to go on,
    /// which is also the right answer for most accounts.
    ///
    /// Resolved against the providers currently on offer rather than the
    /// shipped list, so a provider the page has stopped listing does not come
    /// back as a button that presses nothing.
    func last(in providers: [SPIDProvider] = SPIDProvider.all) -> PoliMiLoginMethod {
        guard let id = defaults.string(forKey: Self.key) else { return .password }
        switch id {
        case "cie": return .cie
        case "eidas": return .eidas
        case "edugain": return .eduGAIN
        case let id where id.hasPrefix("spid-"):
            let slug = String(id.dropFirst("spid-".count))
            // A provider that has left the federation must not come back as a
            // button that presses nothing.
            guard let provider = providers.first(where: { $0.slug == slug })
            else { return .password }
            return .spid(provider)
        default: return .password
        }
    }

    /// The method used last time, or nil when nothing was recorded: unlike
    /// ``last(in:)``, which falls back to the password, this does not claim a
    /// way in the student may never have used.
    func remembered(in providers: [SPIDProvider] = SPIDProvider.all) -> PoliMiLoginMethod? {
        defaults.string(forKey: Self.key) == nil ? nil : last(in: providers)
    }

    func remember(_ method: PoliMiLoginMethod) {
        defaults.set(method.id, forKey: Self.key)
    }
}
