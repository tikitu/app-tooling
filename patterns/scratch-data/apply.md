# Applying scratch-data

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|scratch-data`.
- **Copied by hand:** the `Makefile` has its own `run-scratch` and
  `scratch-reset` targets (projects made from the starter before this
  pattern, and those that copied them). Compare them with
  `files/mk/scratch-data.mk`; the step below replaces them. A
  `quit-running` macro of the project's own goes too, since the fragment
  defines it.
- **Something else doing this job.** Look for:
  - a launch argument or environment variable that picks another database
    (`--scratch`, `--demo`, `-database`, a `UserDefaults` argument);
  - a separate scheme, configuration or bundle id for a test copy of the
    app;
  - `run-adhoc`, `run-test` or similar targets, and what data they open.

  If any of these exist, describe what the project does and what this
  pattern would do instead to the user, and ask, before changing anything.
- **Not adopted:** the app opens one database, whoever launches it.

## Parameters

| Parameter | Where to find it |
|---|---|
| `APP` | the `Makefile`'s path to the built bundle, usually `build/<App>.app` |
| `BUNDLE_ID` | the Mac app's bundle id: `Resources/Info.plist`, `build.sh` or the `Makefile` |
| `SCRATCH_DIR` | where the app's code puts the scratch database (below). Sandboxed: `$(HOME)/Library/Containers/$(BUNDLE_ID)/Data/tmp/<App>-scratch`. Unsandboxed: `URL.temporaryDirectory` is `$TMPDIR`, so `$(shell getconf DARWIN_USER_TEMP_DIR)<App>-scratch` |
| `SCRATCH_DEFAULTS` | the scratch defaults suite. Sandboxed: `$(HOME)/Library/Containers/$(BUNDLE_ID)/Data/Library/Preferences/$(BUNDLE_ID).scratch`. Unsandboxed: `$(BUNDLE_ID).scratch`. Empty if the app has no settings |
| `SCRATCH_BUILD` | the target that builds `$(APP)`, if it is not `build`. For an app that syncs, one that builds a bundle which cannot (`sync-configuration`) |

Whether the app is sandboxed: `com.apple.security.app-sandbox` in its
entitlements.

## Steps

The project must already have `pattern-imports`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|scratch-data: ./
    app-tooling|scratch-data-docs: docs/app-tooling/scratch-data/
```

and beside the other rules:

```yaml
rule scratch-data:
    export: patterns/scratch-data/files
rule scratch-data-docs:
    pick: [patterns/scratch-data/README.md, patterns/scratch-data/apply.md, patterns/scratch-data/CHANGELOG.md]
    export: patterns/scratch-data
```

Then `uvx peru@1.3.5 sync`, which puts `mk/scratch-data.mk` in place. If
the project has its own `run-scratch`, delete it and its `scratch-reset`
and `quit-running` first (step 3), or `make` will warn about overridden
recipes.

**2. The app's `--scratch-database`.** Where the Mac app starts, before the
database is opened:

```swift
/// `--scratch-database` runs on scratch data: its own database and user
/// defaults, and no sync. `make run-scratch` launches it this way.
static let isScratch = CommandLine.arguments.contains("--scratch-database")
```

- **The database:** when `isScratch`, open
  `URL.temporaryDirectory.appending(path: "<App>-scratch", directoryHint: .isDirectory)`
  `/scratch.sqlite` instead of the real file, creating the directory. Same
  migrations; nothing is copied from the real database.
- **User defaults:** when `isScratch`, use
  `UserDefaults(suiteName: "<bundle id>.scratch")` wherever the app reads
  settings (with SwiftUI, `.defaultAppStorage(_:)` on the root view), so a
  scratch run neither reads nor changes the real settings.
- **Sync:** when `isScratch`, do not start it. Put the condition where sync
  is started, not inside the sync code, so it is visible at launch.

The starter's `Mac app entrypoint.swift` and `Core/Schema.swift`
(<https://github.com/tikitu/app-tooling/tree/main/starter/Packages>) are a
worked example.

**3. The Makefile.** Set the parameters and include the fragment, after the
target that builds the app:

```make
# Scratch data for agents (app-tooling: scratch-data): `make run-scratch`,
# `make scratch-reset`. docs/app-tooling/scratch-data/.
SCRATCH_DIR      := $(HOME)/Library/Containers/$(BUNDLE_ID)/Data/tmp/MyApp-scratch
SCRATCH_DEFAULTS := $(HOME)/Library/Containers/$(BUNDLE_ID)/Data/Library/Preferences/$(BUNDLE_ID).scratch
include mk/scratch-data.mk
```

Add `run-scratch` and `scratch-reset` to `help`. The project's own `run`
targets can use `$(quit-running)` before `open`.

**4. `AGENTS.md`**, where it says how to run the app:

> Run the Mac app with `make run-scratch`, never `make run`: it launches in
> the background on scratch data (`--scratch-database`), which never syncs.
> `make scratch-reset` throws that data away.

**5. Record it** in `app-tooling.toml`:

```toml
[patterns.scratch-data]
```

## Verify

- `make -n run-scratch` prints the build, then
  `open -g -n "<APP>" --args --scratch-database`.
- `make scratch-reset SCRATCH_DIR=` exits non-zero with
  `✗ SCRATCH_DIR ('') must name a directory containing "scratch"`.
- `make run-scratch`, then `pgrep -fl "<App>.app/Contents/MacOS/"` shows
  the process with `--scratch-database`, and `ls "<SCRATCH_DIR>"` shows
  `scratch.sqlite`. Run this only for an app whose scratch run cannot reach
  real data: never before step 2 is in, and for an app that syncs, only with
  a build that cannot (`sync-configuration`).
- `make scratch-reset`; then `ls "<SCRATCH_DIR>"` fails with "No such file
  or directory".
