import Foundation
import Observation
import OSLog

/// The SPID providers the Politecnico federates with, kept from the login page
/// itself.
///
/// ``SPIDProvider/all`` is the shipped list, read off the live page on 2026-09-12.
/// The federation changes, and a provider whose identifier moves becomes a button
/// that presses nothing, so the app runs ``extractionScript`` while the page is
/// loaded and ``adopt(_:)`` keeps what it read in `UserDefaults`.
///
/// The list is therefore one sign-in behind: the first sign-in uses the shipped
/// list and refreshes it, and every sign-in after that uses what the page last
/// said. The alternative would be a full authorisation round trip at launch, for a
/// list the student may never need, against a page that sets a session cookie.
@MainActor
@Observable
final class SPIDCatalogue {
    /// Defaults key the adopted list is stored under, as raw JSON.
    private static let key = "spidProviders"

    /// Where the remembered method is persisted.
    /// Where the adopted list is persisted.
    private let defaults: UserDefaults
    /// Diagnostic log for this type, under the `oauth` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "oauth")
    /// The list last read from the page, or `nil` before one has been adopted.
    private var stored: [SPIDProvider]?

    /// Creates the memory.
    ///
    /// - Parameter defaults: Where the remembered method is persisted.
    /// Reads any previously adopted list.
    ///
    /// - Parameter defaults: Where the list is persisted.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = Self.decode(defaults.string(forKey: Self.key))
    }

    /// The providers to offer: the last list read from the page, or the shipped list.
    var providers: [SPIDProvider] { stored ?? SPIDProvider.all }

    /// Takes the list ``extractionScript`` just reported.
    ///
    /// An unreadable or empty result is ignored rather than adopted: the page is not
    /// the app's, and an empty list would be a sign-in method silently disappearing.
    /// An unchanged list is not rewritten.
    ///
    /// - Parameter json: The script's result.
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

    /// Decodes the script's result into providers.
    ///
    /// An entry with no slug cannot be pressed and one with no identifier has no
    /// fallback, so either is dropped.
    ///
    /// - Parameter json: The script's result.
    /// - Returns: The providers, or `nil` when nothing usable decodes.
    private static func decode(_ json: String?) -> [SPIDProvider]? {
        guard let data = json?.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return nil }
        // An entry with no slug cannot be pressed, and one with no id has no
        // fallback either. Either way it is better left out than offered.
        let providers = entries.compactMap(\.provider)
        return providers.isEmpty ? nil : providers
    }

    /// One provider as ``SPIDCatalogue/extractionScript`` reports it.
    private struct Entry: Decodable {
        /// The `data-idp` value.
        let slug: String
        /// The `id_idp` value from the button's `formaction`.
        let identifier: String
        /// The page's accessible label for the provider.
        let name: String?

        /// The entry as a ``SPIDProvider``, or `nil` when the slug or identifier is empty.
        ///
        /// A missing label falls back to the slug, which is ugly on a button and still
        /// usable.
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
    /// Each provider is an `li` carrying `data-idp`, wrapping a submit button whose
    /// `formaction` holds `id_idp`, and a `.spid-sr-only` span holding the accessible
    /// name — the only plain-text name on the page, the visible one being part of a
    /// logo image.
    ///
    /// Evaluates to a JSON array of `{slug, identifier, name}`, which ``adopt(_:)``
    /// takes.
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

/// Which way in the student used last time, so it can be offered first.
///
/// A student signs in with the same thing every time — their password, or the one
/// SPID provider they hold. The remembered method becomes the primary button and
/// the others stay where they were.
@MainActor
@Observable
final class LoginMethodMemory {
    /// Defaults key the method's ``PoliMiLoginMethod/id`` is stored under.
    private static let key = "lastLoginMethod"

    /// Where the remembered method is persisted.
    private let defaults: UserDefaults

    /// Creates the memory.
    ///
    /// - Parameter defaults: Where the remembered method is persisted.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The method to offer first, falling back to ``PoliMiLoginMethod/password``.
    ///
    /// A remembered SPID provider is resolved against the providers currently on offer,
    /// so one that has left the federation does not return as a button that presses
    /// nothing.
    ///
    /// - Parameter providers: The providers currently on offer, from
    ///   ``SPIDCatalogue/providers``.
    /// - Returns: The method to make primary.
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

    /// The method used last time, or `nil` when nothing has been recorded.
    ///
    /// Unlike ``last(in:)``, this does not claim a way in the student may never have
    /// used.
    ///
    /// - Parameter providers: The providers currently on offer.
    /// - Returns: The remembered method, or `nil`.
    func remembered(in providers: [SPIDProvider] = SPIDProvider.all) -> PoliMiLoginMethod? {
        defaults.string(forKey: Self.key) == nil ? nil : last(in: providers)
    }

    /// Records the method the student just used.
    ///
    /// - Parameter method: What they chose.
    func remember(_ method: PoliMiLoginMethod) {
        defaults.set(method.id, forKey: Self.key)
    }
}
