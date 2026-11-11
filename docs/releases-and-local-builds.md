# Releases, beta features and local builds

The private build-control repository is `samuelesegrini/PoliVerse-builds`.
The phone starts a workflow there; the logged-in Mac builds and optionally
installs on its paired iPhone. No TestFlight or paid Apple membership is
required to trigger builds. Device signing remains an Xcode prerequisite.

See [the runner guide](../automation/github-builds/README.md) for setup, phone
controls, scheduling, logs, and stopping the service. The private repository
is deployed separately from these public templates.

## A release

1. Add student-facing changes to `ReleaseNotes.all`, newest first. Keep the
   headline and three or four concrete things a student can do. Exclude build
   machinery from those notes.
2. Update `MARKETING_VERSION` together for the app, widgets, Watch app and
   Watch widgets. The notes version must match the app's version exactly.
3. Run unit and navigation tests, including `ReleaseControlsUITests` after
   changing Settings. Check light/dark and large text.
4. Merge the reviewed feature PR. The private workflow's next scheduled check
   tests/builds `main`. For a phone install, run it manually with platform
   `device` and `install` enabled.

An existing installation shows unseen release notes after onboarding. A new
install skips the update sheet. Settings keeps both the current notes and
history available. Rebuilding the same marketing version changes the build
number/provenance but does not show the update sheet again.

The build runner stamps the full source commit into the bundle. Settings
links to that exact commit; normal Xcode builds omit that link. Build products
and logs stay on the Mac. Scheduled builds use a dedicated simulator, not the
simulator someone has open for development.

## A beta feature

`BetaFeature` is the catalog. Give each case a stable raw identifier, title,
description, and availability rule. `FeatureFlags` owns per-install opt-in
preferences, availability enforcement, and reset. Inject it from the app and
previews; views read it through the environment.

Gate the actual feature entry point with `flags.isEnabled(...)`, not just its
Settings switch. Keep a working fallback. Test default-off, persistence,
availability taking precedence over old saved values, and reset. Shared
widgets/Watch do not automatically inherit phone preferences; explicitly
synchronize a flag if a future experiment spans those processes.

Campus 3D is the first experiment: Debug on iOS only, off until opted in.
Release and Mac builds keep Apple Maps even if defaults contain an old opt-in.
The former `campusMapKind` preference is superseded; existing installs start
with the safe Apple Maps fallback until they opt in on the new page.

These flags are local switches for bundled code. There is no configuration
server or remote kill switch. Add remote configuration only when needed, with
validated data, cached defaults and explicit expiry/failure behavior.
