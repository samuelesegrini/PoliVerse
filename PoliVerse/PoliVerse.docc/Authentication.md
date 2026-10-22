# Signing in

How a student gets into the Politecnico's services, and into WeBeep.

## Overview

There are two front doors, and they are separate on purpose.

| | Politecnico services | WeBeep |
|---|---|---|
| **What it opens** | timetable, libretto, exam enrolments | course materials, forums, assignments |
| **How** | OAuth against `oauthidp.polimi.it` | a Moodle session of its own |
| **Held by** | ``TokenStore`` | ``WeBeepModel`` |
| **Can lapse** | independently | independently |

> Important: The Politecnico token does not carry the WeBeep session. The app
> says this outright — in the first run (``WeBeepStepView``) and in
> Impostazioni · Collegamenti — rather than leaving the WeBeep tab looking
> broken when only one of the two has expired.

### The Politecnico

![The OAuth sign-in as a sequence between the app, the web view, the identity provider and the token store.](oauth-flow)

``PoliMiOAuth`` describes the endpoints. ``LoginFlow`` drives the sequence —
restore at launch, sign in, sign out, and the re-sign-in that moves to another
enrolment — and is the only thing besides ``Session`` allowed to move a session
between states. ``Session`` holds who the student is: their ``Student`` record,
the matricola in use, and the directory the services are resolved through.

> Warning: The app never asks for credentials itself, and must not start. It
> opens the identity provider's own page in a web view (``AuthWebView``,
> ``PoliMiAppLoginWebView``); the provider prompts for a password, SPID or CIE
> and redirects with an authorisation code. Every sign-in screen in the app
> repeats this to the student in as many words.

The client id and the scope list come from ``ServiceDirectory``'s own
`/jaf/oauth/params` rather than from constants in the binary, so a change on
the Politecnico's side needs no release.

> Note: ``TokenStore`` is an actor so that checking and refreshing are atomic.
> The Politecnico rotates the refresh token, so two concurrent refreshes would
> present a token the other has already invalidated and end the session. A
> refresh that fails for transport reasons leaves the stored pair alone —
> losing the network must not lose the session — while one the provider
> actually refuses clears it.

### SPID and CIE

``SPIDCatalogue`` lists the identity providers, and ``PoliMiLoginMethod``
records which way in the student last used, so the button offers it again
(``LoginMethodMemory``). ``CieIDBridge`` and ``CieIDRouter`` hand a CIE
sign-in to the CieID app and catch the callback when it returns.

> Warning: For the Polimi App client, which is the one this app signs in as, the
> Politecnico supports CIE only through "Entra con le tue credenziali CIE", not the
> CieID app's quick route. That form posts to `/idp/login/livello2` on the CIE
> provider's own host, which ``CieIDBridge/isHandoffToCieID(_:method:)`` leaves in
> the web view.

### Second factors

Every sign-in has asked for a second factor since 2022, and the app implements none
of them: each is asked for on a page the student already sees. Polimi 2FA is a code
from an authenticator app after the password, on aunicalogin; with SPID or CIE the
provider asks, with an approval in its own app or an SMS code. What the app does is
keep the page alive around them.

- ``SessionSeeder`` uses the session a Politecnico sign-in leaves behind to sign
  WeBeep and the recordings in before ``LoginWebKit/endSession()`` ends it, so a first
  launch costs one second factor rather than three. A page that would need the
  student ends the attempt, and that service keeps its own sign-in.
- ``IdentityAppHandoff`` recognises a provider page opening its app — PosteID's
  "Accedi più rapidamente" universal link, or a scheme of the provider's own — so
  ``AuthWebView`` opens the app itself and leaves the page polling for the approval.
- ``LoginWebKit/autofillHints`` marks aunicalogin's fields for AutoFill, the code
  field as `one-time-code`, and ``LoginWebKit/codeFieldProbe`` lets the sign-in say
  where the code comes from.

> Important: The app never holds the authenticator's secret, never generates a code
> and never offers a field of its own for one. The Regolamento counts the OTP among
> the credentials a service must not collect (art. 2 lett. a, art. 19 c.6).

### Enrolments

One codice persona can carry several matricole, and the services answer only for
the one signed in with.

> Warning: The token is bound to the matricola it was born with. Moving to
> another enrolment means signing out and back in — ``CareerSwitchView`` says
> so plainly rather than appearing to offer a switch it cannot make.

``CareersModel`` lists the enrolments, and ``CareerStepView`` raises this during
the first run, so nobody spends a week wondering why their exams are missing
because the app is pointed at the triennale they finished.

### Scopes

A token carries the scopes it was granted when it was created.

> Tip: If the Politecnico adds a scope, an existing token will not have it and
> the fix is to sign out and back in. ``ScopeAudit`` records what was asked for
> against what was granted, and Impostazioni reports both — which is usually
> the fastest way to explain a service that answers "not enabled".

### WeBeep

``WeBeepModel`` holds the Moodle session, signed in through
``WeBeepLoginSheet``. It can lapse while the Politecnico session is perfectly
healthy, so ``CoursesPage`` offers its own login card in place of the list
rather than showing an empty one.

## Topics

### The session
- ``Session``
- ``LoginFlow``
- ``LoginStage``
- ``Student``

### OAuth
- ``PoliMiOAuth``
- ``TokenStore``
- ``ScopeAudit``
- ``ServiceDirectory``

### Second factors
- ``SessionSeeder``
- ``IdentityAppHandoff``
- ``LoginWebKit``

### Ways in
- ``PoliMiLoginMethod``
- ``LoginMethodMemory``
- ``SPIDCatalogue``
- ``SPIDProvider``
- ``CieIDBridge``
- ``CieIDRouter``

### Screens
- ``LoginView``
- ``LoginWaitingView``
- ``SigningInView``
- ``PoliMiSignInButton``
- ``AuthWebView``
- ``CareerSwitchView``

### Enrolments
- ``CareersModel``
- ``CareerMismatchBanner``
