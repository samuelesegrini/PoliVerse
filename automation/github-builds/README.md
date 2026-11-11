# PoliVerse builds on your Mac

This folder is the source for a **private** `PoliVerse-builds` repository. Keep
its runner separate from the public app repository. Only the private repository
can queue work on the Mac. Do not add pull-request triggers or register this
runner with the public repository.

## From your phone

Open GitHub → `PoliVerse-builds` → Actions → **Build PoliVerse on Mac** →
**Run workflow**. Leave the control workflow on `main`.

- `source_ref`: branch in the public PoliVerse repository; normally `main` after
  merging. A feature branch can be explicitly selected for testing before merge.
- `platform`: `device` for the paired iPhone, `simulator`, or `mac`.
- `configuration`: `Debug` includes optional beta prototypes; `Release` excludes
  them, even if an old saved switch is on.
- `install`: install the finished device/simulator app. Uncheck for Mac builds.
- `test`: run the unit suite first, on a dedicated `PoliVerse CI` simulator.

Scheduled jobs check `main` about every 15 minutes (GitHub can delay schedules).
They run tests and build for the simulator without installing on your phone.
The single Mac runner processes jobs one at a time; scheduled checks do not
cancel queued manual phone builds. A commit already attempted is skipped; manually run the workflow to retry a
failure. GitHub may disable scheduled workflows in an inactive repository.

The Mac must be awake, logged in, online, and running the runner. `caffeinate`
prevents idle sleep during a job; it cannot wake a sleeping or closed Mac.
The iPhone must be paired, reachable by Xcode, and permit developer installs.
Signing must already work in this Mac's logged-in user's Xcode account.
A free Personal Team expires after seven days and does not support every
capability. Build failures report signing problems; the script never strips
app groups or changes the app identifier to conceal them.

## Setup and maintenance

From the PoliVerse repository run `python3 automation/github-builds/setup.py`.
It uses the existing `gh` login, creates the private repository, publishes these
files, downloads and verifies GitHub's Apple Silicon runner, and installs it as
a login-session service. Credentials are registered directly with the runner;
no token goes into the source repository or workflow.

Set the private repository variable `POLIVERSE_DEVICE_ID` to the iPhone UDID
from `xcrun devicectl list devices`. No device ID is needed for simulator builds.

Everything lives under `~/Library/Application Support/PoliVerseBuilds`:

- `runner`: GitHub runner and its service controls (`svc.sh status/start/stop`).
  Its work directory is `~/.local/share/poliverse-builds/work`: GitHub shell
  steps require that path to contain no spaces.
- `control`: private workflow checkout used for setup and later updates.
- `source`: disposable, managed checkout of the public app, separate from your work.
- `DerivedData`: incremental build products.
- `logs`: full build, test and installation logs, retained locally.

Job summaries show the commit, result, and local paths. No app data, signing
files, or logs are uploaded as public artifacts. The service runs with this
Mac user's permissions: only trusted maintainers should access the private
repository or merge executable changes into the source being built.

After changing this folder, copy `build.py`, `README.md`, and `.github/` to the
private control checkout and commit/push there. The live private repository is
a separate deployment; editing the public template alone does not update it.

To stop automation, disable the workflow in GitHub and run `./svc.sh stop`
inside the runner directory. To remove it, run `./svc.sh uninstall`, then
remove the runner in the private repository's Settings → Actions → Runners.
