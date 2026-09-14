# WeBeep

**No scraping needed.** WeBeep is a stock Moodle, and Moodle ships a supported
handshake for getting an API token on an SSO-only site. The earlier note in
[polimi-auth.md](polimi-auth.md) called this unresolved; it is resolved.

## The flow

```
1. GET https://webeep.polimi.it/auth/shibboleth/index.php
       ↓ user authenticates at shibidp.polimi.it (aunicalogin / SPID)
2. →   https://webeep.polimi.it/my/            ← session cookie now exists
3. GET /admin/tool/mobile/launch.php?service=moodle_mobile_app
           &passport=<nonce>&urlscheme=poliverse
       ↓
4. →   poliverse://token=<base64>
       base64 decodes to  siteid:::token[:::privatetoken]
5. Every call thereafter:
   GET /webservice/rest/server.php?wstoken=…&wsfunction=…&moodlewsrestformat=json
```

Implemented in `Services/WeBeepAuth.swift`, `WeBeepLoginView.swift`,
`WeBeepAPI.swift`, `WeBeepService.swift`.

## Evidence this works

Probed live on 2026-09-11:

```
$ curl -sI "https://webeep.polimi.it/admin/tool/mobile/launch.php\
?service=moodle_mobile_app&passport=12345&urlscheme=poliverse"

HTTP/1.1 303 See Other
X-Redirect-By: Moodle
Set-Cookie: tool_mobile_launch={"service":"moodle_mobile_app","passport":"12345",
                                "urlscheme":"poliverse","confirmed":0,"oauthsso":0}
Location: https://webeep.polimi.it/login/index.php
```

The `tool_mobile` plugin is enabled, the mobile service is accepted, and Moodle
stored **our own** `urlscheme`. Also confirmed live: `/webservice/rest/server.php`
answers (`invalidtoken` for a bad token) and `/auth/shibboleth/index.php`
redirects into `shibidp.polimi.it`.

### Payload format, from Moodle source

`admin/tool/mobile/launch.php` (MOODLE_405_STABLE, lines ~108–124):

```php
$siteid = md5($CFG->wwwroot . $passport);
$apptoken = $siteid . ':::' . $token->token;
if ($privatetoken and is_https() and !$siteadmin) { $apptoken .= ':::' . $privatetoken; }
$apptoken = base64_encode($apptoken);

$forcedurlscheme = get_config('tool_mobile', 'forcedurlscheme');
if (!empty($forcedurlscheme)) { $urlscheme = $forcedurlscheme; }
$location = "$urlscheme://token=$apptoken";
```

Two things fall out of this that guesswork would have missed:

- **The private token is often absent.** It is withheld unless the user just
  logged in. A two-part payload is normal, not an error.
- **`forcedurlscheme` can override our scheme**, and it is applied *after*
  login — so probing the launch endpoint beforehand cannot reveal it; the
  cookie echoes back whatever we asked for either way. The interceptor
  therefore accepts `moodlemobile://` as well as `poliverse://`. That
  `webeep-sync` registers a handler for `moodlemobile` specifically suggests
  WeBeep does force it.

## Prior art

| Project | Method |
| --- | --- |
| [`toto04/webeep-sync`](https://github.com/toto04/webeep-sync) (Electron, maintained 2026) | `launch.php` + `moodlemobile://` intercept. Same flow as ours. Hardcodes `passport=12345` and skips the signature check. |
| [`matteovisotto/myPoliFile`](https://github.com/matteovisotto/myPoliFile) (Swift, App Store) | After SSO, loads `login/token.php?username=<codicePersona>@polimi.it&password=&service=moodle_mobile_app` and scrapes the JSON from the page body. |

The `token.php` route works but needs the person code and relies on
empty-password login being permitted for SSO accounts, so it is one policy
change away from breaking. `launch.php` is the officially supported path and
needs nothing but the session.

Neither project verifies the `siteid` signature. We do: the passport is random
per attempt and the payload must be signed for it. The redirect is cancelled
inside our own `WKWebView` before iOS sees it, so this is defence in depth
against a hostile page rather than the only safeguard — but it is nearly free.

## Web service functions

Taken from myPoliFile, which exercises the whole surface:

| Function | Use |
| --- | --- |
| `core_webservice_get_site_info` | our own `userid` — needed by the next call |
| `core_enrol_get_users_courses` | enrolled courses |
| `core_course_get_contents` | sections → modules → files |
| `core_course_search_courses` | find non-enrolled courses |
| `core_user_get_users_by_field` | profile lookup |
| `mod_forum_get_forum_discussions` / `..._get_discussion_posts` | forums |
| `message_popup_get_popup_notifications` | notifications |
| `enrol_self_enrol_user` | self-enrolment |

We use the first three, plus (for the updates feed, verified against Moodle
4.5 source) `mod_forum_get_forum_discussions` for the announcements forum and
`mod_assign_get_assignments` for deadlines — see
[academic-intelligence-layer.md](academic-intelligence-layer.md).

## Gotchas

- **Moodle reports errors with HTTP 200** and an error object in the body.
  Checking the status code alone decodes an error as an empty result, showing
  an empty course list instead of "session expired". `WeBeepAPI` sniffs for the
  error shape before decoding.
- **File URLs need the token on the query string** (`pluginfile.php?token=…`).
  So the token appears in the URL of every download — don't log those URLs or
  pass them outside the app.
- **PoliMi and Moodle share no course identifier.** Moodle has a numeric id and
  a free-text `fullname`; PoliMi uses `c_insegn_piano`. We match on the code
  appearing inside the Moodle title first, then fall back to normalised names.
  This is the weakest link in the chain and the first thing to check if a
  course shows no materials.
- **Two independent sessions.** The WeBeep token and the PoliMi OAuth token
  have separate lifetimes; either can die while the other lives. They are
  stored under separate Keychain accounts and `WeBeepService` drops its token
  on `invalidtoken` so the UI offers a re-login rather than retrying forever.

## Still unverified

Everything above is confirmed by live probes, Moodle's source and two working
implementations — but the end-to-end flow has **not** been run against a real
account, because that needs the user's credentials. What to watch on the first
real login:

1. Whether `forcedurlscheme` redirects to `moodlemobile://` instead (handled).
2. Whether Moodle shows a confirmation interstitial — `confirmed:0` in the
   cookie suggests it might, and the flow may need one extra click through.
3. Whether the signature check passes, i.e. that `$CFG->wwwroot` is exactly
   `https://webeep.polimi.it` with no trailing slash.
4. Whether course-name matching actually finds each course.
