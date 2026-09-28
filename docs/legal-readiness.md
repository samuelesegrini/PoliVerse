# Legal and App Store readiness — 2026-09-28

Is PoliVerse legal to ship, and will it pass App Review? Written from the code
at `7c0bced`, the repo's own research (chiefly
[academic-intelligence-layer.md](academic-intelligence-layer.md) §18), the App
Review Guidelines as published today, and PoliMi's public rules.

**This is not legal advice.** It reports what the rules say and where the code
stands against them. The questions only PoliMi can answer are listed at the end.

## Verdict

**Not ready to ship yet.** Five things block a submission or make a rejection
likely, and all are fixable in about a day (items 1–5). One risk cannot be fixed
in code: PoliVerse has no permission from PoliMi to use its private APIs, and its
login reuses the official client's identity (item 6). That does not make the app
illegal in any way found here, but it is the thing most likely to end it, through
App Review under 5.2.2 or through PoliMi objecting.

## What is already right

These are the parts that usually sink apps like this, and PoliVerse gets them right:

- **No password handling.** Credentials are typed only into the ateneo's own page in
  a web view. PoliMi's Regolamento D.R. 6751/2025 art. 19 c.6 forbids service
  providers from collecting or storing credentials; PoliVerse does neither.
- **No server, no analytics, no third-party SDKs.** Every host in the code is PoliMi,
  WeBeep, Webex (through recman), Apple or Outlook. Nothing reaches the developer.
- **Tokens only in the Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- **Read-only by decision.** It never enrols, refuses a mark or posts
  ([writes-to-university-systems.md](writes-to-university-systems.md)).
- **Disclaimers are present:** "PoliVerse non è affiliata al Politecnico di Milano",
  "non è un'app ufficiale", "Non è un documento ufficiale" on the card, and a
  recordings notice about other participants' voices.
- **Other students' data is minimised.** `ResultsFileReader` keeps only the student's
  own line from a results file.
- **Recording downloads respect Webex's `preventDownload` flag**, and the app skips
  the chat and the participant list.
- **Calendar usage strings** are present for both full and write-only access.

## Blockers

### 1. No privacy policy — Guideline 5.1.1(i)

> All apps must include a link to their privacy policy in the App Store Connect
> metadata field and within the app in an easily accessible manner.

Nothing in the app links a policy; the only "Privacy" heading is in
`NotificationSettingsView.swift:266`, and it covers what notifications show. Even
an app that collects nothing needs a policy. It should say:

- what the app reads (career, timetable, WeBeep, recordings);
- that it all stays on the device and the developer receives none of it;
- that the app talks directly to PoliMi, WeBeep and Webex, whose own policies apply;
- that results files are read on the device, and only the student's own line is kept;
- the diagnostics report, which leaves the device only when the user shares it;
- how to delete everything (sign out, or delete the app);
- a contact address.

Host it anywhere public (a GitHub Pages page is enough). Add it to App Store Connect
and to Settings.

**App Privacy label:** "Data Not Collected" is probably accurate. Apple counts data
as collected only when it leaves the device in a way the developer or its partners
can access, and here none does. The one edge is the diagnostics report. It is
shared only when the user chooses to, but if it reaches you by email, disclose it
in the label as Diagnostics, not linked to the user.

### 2. No privacy manifest — upload rejected with ITMS-91053

**Fixed.** `PrivacyInfo.xcprivacy` is now in `PoliVerse/`, `PoliVerseWidgets/`,
`PoliVerseWatch/` and `PoliVerseWatchWidgets/`, and the synchronised groups copy
each into its own bundle. None goes in `Shared/`, which every target compiles: two
manifests in one bundle collide at build time. The app declares `CA92.1` and `1C8F.1`
(user defaults), `C617.1` (file timestamps) and `54BD.1` (active keyboards); the
extensions declare only the two user-defaults reasons, since they compile only
`Shared/`, whose app-group suite falls back to `.standard`. There is no tracking and
no collected data. The codes were checked against Apple's
`NSPrivacyAccessedAPIType` reference on 2026-09-28. Add a declaration whenever new
code touches a listed API.

What follows is the original finding.

No `PrivacyInfo.xcprivacy` exists in any target. Since May 2024, App Store Connect
rejects the upload when the code uses a required-reason API without declaring it.
The code uses:

| API category | Where | Likely reason code |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | 57 files (`UserDefaults` / `@AppStorage`, including the app group) | `CA92.1`, plus `1C8F.1` for the app group |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `ReportArchive.swift:153` (`contentModificationDateKey`) | `C617.1` |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | `StickerViews.swift:553` (`activeInputModes`) | `54BD.1` |

Add one manifest to each target: app, widgets, Watch app and Watch widgets. Set
`NSPrivacyTracking = false` and give an empty collected-data list. Check the reason
codes against Apple's current list when you add them.

### 3. PoliMi logo, seal and building photo — Guidelines 5.2.1 and 4.1

**Fixed.** The `PolimiLogo`, `PolimiSeal` and `PolitecnicoFacade` assets are deleted.
So is the code's fallback, a portico seal beside "POLITECNICO MILANO 1863" set in
type, which was a look-alike of the ateneo's mark in its own right. The card now
carries PoliVerse's mark: the app icon's orbit (planet, ring and moon) drawn as a
line (`OrbitMark` in `StudentCard.swift`) beside the name "PoliVerse", with a large
faint orbit on a navy ground where the photo stood. "Non è un documento ufficiale"
stays on the back.

What follows is the original finding.

`StudentCard.swift` draws `PolimiLogo`, `PolimiSeal` and `PolitecnicoFacade` on a
card styled like a student ID. That is three problems:

- **Trademark.** 5.2.1 says: "Don't use protected third-party material such as
  trademarks … without permission". PoliMi's communication guidelines say the Rector
  approves each use of the logo. Even student associations are not allowed to use
  it, and requests go to `comunicazione@polimi.it`.
- **Look-alike of an official document.** A card that looks like a student ID and
  carries the ateneo's seal is exactly what a reviewer or PoliMi reads as
  impersonation (4.1(b)), disclaimer or not.
- **The facade photo has no recorded source or licence.** It came in with `c60fb17`
  and nothing says where it is from.

Fix: remove all three assets from the shipping build. The code already falls back
to a placeholder seal with the name in type when the assets are missing. Put the
PoliVerse mark or a neutral illustration in its place. Also keep "Politecnico" and
"PoliMi" out of the app name and subtitle. Saying "for Politecnico di Milano
students" in the description, next to the disclaimer, is ordinary descriptive use.

### 4. Review access — Guideline 2.1

The app is built around a login that a reviewer cannot pass, because they have no
PoliMi account. 2.1 allows "a built-in demo mode in lieu of a demo account **with
prior approval by Apple**". The sample-data mode is that demo mode. So:

- In the review notes, say that the app is a client for university accounts,
  that sample data shows every screen, and how to turn it on.
- Expect a follow-up question, and if you can, ask for approval ahead of time
  through App Review contact.
- Rethink "mock data on by default" (README). If a first launch shows Mario Rossi's
  grades without explanation, that can read as placeholder content. The onboarding
  already offers "Esplora con dati di esempio" as a choice, which is better.

### 5. EU trader status — Digital Services Act

Since 17 February 2025, the EU App Store drops apps whose developer has not
declared trader status. Declare it in App Store Connect before you submit:

- **Non-trader:** free, no monetisation, not part of a business. No contact details
  are published.
- **Trader:** your address, phone and email appear on the product page.

A free student app with every icon free fits non-trader. If you add paid features
later, you must switch to trader.

## The structural risk

### 6. Permission to use PoliMi's systems — Guideline 5.2.2

> If your app uses, accesses … or displays content from a third-party service,
> ensure that you are specifically permitted to do so under the service's terms of
> use. **Authorization must be provided upon request.**

Where things stand:

- **No terms of use** for Servizi Online, the PoliMi APIs or WeBeep were found
  (§18.1). Nothing forbids an unofficial client, and nothing allows one.
- **The WeBeep path is the defensible one.** It uses Moodle's supported
  `tool_mobile` handshake, which the ateneo has switched on, and myPoliFile has been
  on the App Store for years doing the same thing.
- **The Servizi Online path is harder to defend.** The login uses the official
  app's OAuth `client_id` (`1057407812`) and reads the credential the official web
  app stores in `sessionStorage` (`24344_oauthCredentials`). To PoliMi's servers,
  PoliVerse therefore looks like the official client. That works, and it is
  documented honestly in [polimi-auth.md](polimi-auth.md). It is also the hardest
  part to defend if App Review asks for authorisation, or if PoliMi objects under
  art. 21 c.2 ("usare esclusivamente le funzionalità … alla cui fruizione risulta
  abilitato").
- **The risk falls on the students too.** Under art. 37 the ateneo monitors logs and
  can suspend credentials. Polling is already modest (IAE ≤ 1 pass per 15 min,
  WeBeep updates ≤ 1 per hour, free rooms per minute while the page is open), which
  helps.

The only thing that turns grey into green is **written permission from PoliMi**.
Write to the ICT services, and copy `privacy@polimi.it` (the contact named in the
Regolamento, art. 21 c.2). Describe the app as read-only, on-device, no server, no
password handling, with the source available, and ask for:

1. permission to use the private APIs;
2. ideally, a client ID or URL scheme of your own, so you can stop borrowing the
   official one;
3. a position on recording downloads (item 7).

A reply, even an informal one, is what you show App Review if they ask. Without
one, a first submission may pass, but any complaint or reviewer question can
remove the app.

## Worth fixing before launch

### 7. Downloading lecture recordings — Guideline 5.2.3

5.2.3 forbids downloading media from third-party sources "without explicit
authorization from those sources". The app does honour Webex's `preventDownload`
flag, which the ateneo or the lecturer sets, so downloads only happen where the
platform allows them. That is a real authorisation signal, but it is not the
"explicit authorization" the guideline asks for. Recordings also contain other
students' voices and faces. The lowest-risk v1 streams recordings and holds back
downloads until the PoliMi reply in item 6 covers them.

### 8. Personal data in the system log

**Fixed.** The matricola is now logged as `.private(mask: .hash)` in `LoginFlow`,
`CareersModel` and `PoliMiAppLoginWebView`, so a log can still tell two accounts
apart without saying which. The profiles payload is logged by size only. The
Manifesto search text is `.private`. A second leak turned up in the same pass:
`PoliMiAPI.send(_:as:)` logged up to 1,200 bytes of any response body that failed
to decode, publicly, which for a career payload means marks. It now logs the
decoding error's key path (keys and indices, never values) and the byte count.
The 401 bodies stay public: they are the gateway's error messages, which
[polimi-auth.md](polimi-auth.md) relies on for diagnosis.

What follows is the original finding.

The repo's own rule is to log "forme, mai valori" (shapes, never values). Three
lines break it by marking personal values `privacy: .public`, which puts them in
the unified log in the clear and into any sysdiagnose:

- `Session.swift:164` logs the first 500 bytes of the raw `/jaf/internal/profiles`
  payload;
- `LoginFlow.swift:184` and `:211` log the matricola.

Make these `.private`, or log only shapes. I did not check what the shareable
diagnostics report contains; look at it the same way before release.

### 9. Export compliance

The app uses only HTTPS and Apple's crypto, so it qualifies for the exemption. Set
`ITSAppUsesNonExemptEncryption = NO` in the Info.plist so App Store Connect stops
asking on every upload.

### 10. Code derived from other projects

[polimi-auth.md](polimi-auth.md) says the flow was "reverse-engineered from
PoliFemo … then simplified". Knowing a protocol raises no copyright issue. Copied
code does: if any source was copied verbatim from PoliFemo, myPoliFile, webeep-sync
or the CieID SDK, check that project's licence and comply with it. There are no
package dependencies, so there is nothing else to attribute.

## EU law, one regulation at a time

Italy is in the EU, so all of these apply wherever PoliVerse ships. For each law,
the question is whether PoliVerse falls under it at all. Most of these laws hinge
on two facts: **no personal data reaches the developer**, and **the app is free
with no monetisation**. Change either, and several rows below change with it.

| Law | Applies? | Why | Action |
| --- | --- | --- | --- |
| **GDPR** (2016/679) | Barely, as things stand | Everything is processed on the student's device, for the student. The developer receives nothing, so for the app's core function the developer is probably not a controller. That changes the moment personal data reaches you: a diagnostics report or a support email makes you the controller for that data, with an art. 13 notice, a retention period and data-subject rights. | The privacy policy (item 1) doubles as the art. 13 notice. Say how long you keep support email and diagnostics, and give a contact. Never add a server holding student data without a DPIA (art. 35). |
| GDPR: data about other people | Handled | Results files (other students), teacher contacts (public staff data), recordings (voices and faces) are read on the device and minimised (`ResultsFileReader`, no chat or participant list). | Keep it that way. Don't add sharing or indexing of other people's rows. |
| **ePrivacy** art. 5(3) | No consent needed | Storing on the device (Keychain, cache, `UserDefaults`) is "strictly necessary" for the service the user asked for. Nothing tracks the user, fingerprints the device or reports home. | None. No consent banner. Adding analytics or a crash SDK changes this. |
| **Digital Services Act** | Trader status only | PoliVerse is not an intermediary: it hosts no one's content for others. The one DSA duty that touches it goes through Apple's trader declaration (item 5). | Declare non-trader. |
| **AI Act** (2024/1689) | Minimal | `NoticeSummary` uses Apple's on-device model to summarise a notice. Apple is the provider and carries the Art. 50(2) marking duty. For deployers, Art. 50(4) covers only text published "to inform the public on matters of public interest", and a private summary shown to one student is not that. It is not high-risk either: Annex III §3 covers AI that grades, admits or monitors students, and this does none of those. | Good practice: change the label "Riassunto sul dispositivo" to say it is *generated automatically*, e.g. "Riassunto generato automaticamente sul dispositivo". The UI already keeps the original notice underneath. |
| **Cyber Resilience Act** (2024/2847) | Probably not, while free | It covers products "made available on the market in the course of a commercial activity". A free app with no ads, no in-app purchases and no data collection, from an individual, sits outside that. Recital 15 counts even donations above your costs as commercial. | If you add payment, ads, sponsorship or donations beyond costs, you are in scope. Vulnerability and incident reporting has applied since **11 Sept 2026** (ENISA's single reporting platform); the full essential requirements apply from **11 Dec 2027**. Check the Commission's July 2026 guidance before monetising. |
| **European Accessibility Act** (2019/882) | No | It covers listed consumer services (e-commerce, banking, transport, e-books, communications). A student companion app is not one of them, and service microenterprises are exempt anyway. | None required. The app's automated accessibility audits are good practice regardless. |
| **Database right** (96/9/EC; Italy L. 633/1941 art. 102-bis/ter) | Low risk as built | The Manifesto degli studi, course pages, room catalogue and floor plans are PoliMi databases. A lawful user may extract insubstantial parts (art. 102-ter), which is what the app does: on demand, from each student's device. What the right forbids is repeated, systematic extraction that substitutes for the original. | Never build a server that mirrors the catalogue or re-hosts the floor plans. |
| **Copyright** (course material) | Low | Offline copies of WeBeep files and recordings are the student's own copies under their own access. The Share button in `CourseMaterialsView.swift:134` and `MacCoursesView.swift:375` lets a user pass a lecturer's file on, which is the user's own act. | Acceptable. Don't build any feature that redistributes material between users. |
| **Consumer law** (Digital Content Directive 2019/770) | No | It applies when the consumer pays a price or provides personal data to the trader. Neither happens. | Changes if you monetise. |
| **DMA, NIS2, P2B** | No | These regulate gatekeepers, essential entities and platforms respectively. P2B actually protects you in dealings with Apple. | None. |

**Bottom line for the EU:** as built, PoliVerse is in unusually good shape, because
it has no server, no tracking and no money. The regulations that bite (GDPR as
controller, CRA, consumer law) switch on only if you add one of those. The EU
actions for this release are the privacy policy (item 1), the DSA declaration
(item 5) and the AI-summary label.

**Limits of this check:** I could not read the text of the Commission's July 2026
CRA guidance or `polimi.it` from here (both blocked by this network), so the CRA row
relies on the Regulation and summaries of that guidance. A lawyer, or a university
legal clinic, can confirm the GDPR controller point, which is the one most worth
confirming.

## Checklist

| # | Item | Effort | Blocks submission? |
| --- | --- | --- | --- |
| 1 | Privacy policy (App Store Connect + in-app link) | hours | yes |
| 2 | `PrivacyInfo.xcprivacy` in each target | done | — |
| 3 | Remove PoliMi logo, seal and facade photo | done | — |
| 4 | Review notes + demo-mode explanation | 30 min | likely rejection |
| 5 | Declare DSA trader status | 10 min | yes, in the EU |
| 6 | Ask PoliMi for permission | email + waiting | not at first, but it is the long-term risk |
| 7 | Hold back recording downloads until authorised | small | risk |
| 8 | Make personal values in logs private | done | — |
| 9 | `ITSAppUsesNonExemptEncryption = NO` | 1 min | no |
| 11 | Label AI summaries as generated automatically (AI Act, good practice) | 5 min | no |
| 10 | Check licences of any copied code | review | no |

## Open questions only PoliMi can answer

- Is an unofficial read-only client allowed on Servizi Online, and under which client ID?
- Are there terms of use for Servizi Online, WeBeep or the APIs that were not found here?
- May students download recordings that Webex marks downloadable, for personal study?
- Would the ateneo license its name or logo for a student app? (Probably not: even
  associations may not use it.)

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 2.1, 4.1, 5.1.1, 5.2.1, 5.2.2, 5.2.3
- [DSA trader requirements, App Store Connect Help](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/); [removal notice](https://developer.apple.com/news/?id=einwn76m)
- [Required-reason APIs / ITMS-91053](https://www.avanderlee.com/xcode/missing-api-declaration-required-reason-itms-91053/)
- [PoliMi Regolamento trattamento dati e ICT, D.R. 6751/2025](https://www.normativa.polimi.it/fileadmin/user_upload/regolamenti/privacy_e_sicurezza/REGOLAMENTO_trattamento_dati_e_ICT__marzo2025.pdf), as quoted in [academic-intelligence-layer.md](academic-intelligence-layer.md) §18
- [PoliMi Linee guida comunicazione](https://www.normativa.polimi.it/fileadmin/user_upload/regolamenti/linee_guida/Linee_Guida_Comunicazione.pdf) and [Brand manual](https://www.polimi.it/fileadmin/user_upload/Il-Politecnico/brand/Politecnico_di_Milano_Brand_manual.pdf). Read through search summaries: `polimi.it` is blocked from the network this was written on, so confirm the logo rules in the PDFs.
- [PoliMi distance-learning privacy notice](https://www.polimi.it/en/the-politecnico/communication/privacy/distance-learning)
- [EDPB Guidelines 2/2023 on Art. 5(3) ePrivacy](https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf)
- [Cyber Resilience Act](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act); [Commission CRA guidance](https://digital-strategy.ec.europa.eu/en/library/commission-publishes-new-guidance-support-timely-cyber-resilience-act-implementation)
- [AI Act Art. 50 FAQ](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act)
- [European Accessibility Act](https://commission.europa.eu/strategy-and-policy/policies/justice-and-fundamental-rights/disability/european-accessibility-act-eaa_en)
- [EU database protection](https://digital-strategy.ec.europa.eu/en/policies/protection-databases)
- [myPoliFile on the App Store](https://apps.apple.com/us/app/mypolifile/id1585538793) — precedent for an unofficial WeBeep client
