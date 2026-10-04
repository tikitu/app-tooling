# Applying instruments-profiling

Read [`README.md`](README.md) first for what this does and why, and
[`guide.md`](guide.md) for how it is used.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|instruments-profiling`.
  Updates come with `make app-tooling-update`.
- **Copied by hand, before this pattern:** `scripts/profile-mac.sh`,
  `scripts/trace-query.py`, `scripts/trace-compare.py`,
  `scripts/profile-compare.sh` or `scripts/ui-drive.swift` exist but are not
  imported. These scripts started as copies in two projects. `diff` each
  against `files/scripts/`: the app-specific parts (app path, data path,
  how the app is pointed at the copy, scenarios) move into
  `profiling.conf.zsh` (step 2); anything else that differs is either an old
  copy or an improvement that belongs in app-tooling. Then delete the copies
  and import (step 1). A project's existing `plans/` notes on profiling stay:
  they are its findings.
- **Something else doing this job.** Look for `xctrace` in the `Makefile`
  and `scripts/`, `.tracetemplate` files, an XCTest `measure` suite, or a
  `--scenario`-style launch argument in the app. Describe what the project
  has and what this would add to the user, and ask before changing anything.
- **Not adopted:** none of the above. The usual starting point.

## Parameters

Everything goes into the project's `profiling.conf.zsh`; the guide's table
lists every key.

| Parameter | Where to find it |
|---|---|
| `APP_BUNDLE` | the `.app` the Mac build produces: `build.sh`'s output, the Makefile's `APP` variable |
| A build that cannot sync | a Makefile target that signs ad hoc without iCloud entitlements; if the only build is signed with iCloud, add one (step 3) |
| `REAL_DATA` | where the app keeps its data: `Application Support/<app>/…`, `Documents/…`, a container under `~/Library/Containers/<bundle id>/` for a sandboxed app. Search the sources for `applicationSupportDirectory`, `documentsDirectory`, `defaultDatabase` |
| `LAUNCH_ENV` / `LAUNCH_ARGS` | how the app can be told to use other data: an environment variable read where the path is chosen, or a launch argument. If there is none, add one (step 4) |
| `copy_data` | SQLite: the default. A directory or another store: a function that copies it consistently (the app is not running) |
| `ALLOW_OTHER_COPIES` | `1` if the user keeps the real app open all day, as they may for a tracker or a mail client; the guide says what it costs |
| Scenarios | what the user wants faster. Ask; then define the few interactions that show it |

## Steps

The project must already have `pattern-imports`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|instruments-profiling: ./
    app-tooling|instruments-profiling-docs: docs/app-tooling/instruments-profiling/
```

and beside the other rules:

```yaml
rule instruments-profiling:
    export: patterns/instruments-profiling/files
rule instruments-profiling-docs:
    pick: [patterns/instruments-profiling/README.md, patterns/instruments-profiling/apply.md, patterns/instruments-profiling/CHANGELOG.md, patterns/instruments-profiling/guide.md]
    export: patterns/instruments-profiling
```

Then `uvx peru@1.3.5 sync`, which puts the scripts in `scripts/` and
`mk/profiling.mk` in place.

**2. Write `profiling.conf.zsh`** at the repository root. This file is the
project's own; it is never imported. Start from:

```zsh
# profiling.conf.zsh — this app's settings for the app-tooling pattern
# instruments-profiling (docs/app-tooling/instruments-profiling/guide.md).
# Sourced by scripts/profile-mac.sh and scripts/profile-compare.sh.

APP_BUNDLE=build/MyApp.app
BUILD_HINT="make build-adhoc"

# The data the app reads every day. Profiling copies it and points the app at
# the copy; the recorder checks the app never has this file open.
REAL_DATA="$HOME/Library/Application Support/MyApp/db.sqlite"
LAUNCH_ENV=(MYAPP_DATABASE={DATA})        # or LAUNCH_ARGS=(--database {DATA})
describe_data() { sqlite3 "$1" 'select count(*) || " items" from items'; }

# The real app may be open while profiling: its idle CPU is noise, not a risk.
# ALLOW_OTHER_COPIES=1

SCENARIO_NOTIFY_PREFIX=com.example.myapp.scenario
COMPARE_SCENARIOS=(select scroll)
scenario_select() { scenario_args=(--scenario select); scenario_notifies=1; }
scenario_scroll() {
  scenario_args=(--scenario wait); scenario_notifies=1
  drive() {
    $DRIVER scroll-window $PID --lines -8 --times 120 --interval-ms 16
    $DRIVER scroll-window $PID --lines 8 --times 120 --interval-ms 16
  }
}
```

**3. A build that cannot sync**, if the project has none. Usually a variant of
the existing Mac build target that signs ad hoc (`codesign --sign -`) with an
entitlements file holding no iCloud, push or app-group keys. Name it in
`BUILD_HINT`, and as `PROFILE_BUILD` in step 5.

**4. A way to point the app at other data**, if it has none. Where the app
chooses its data path, read an environment variable or launch argument
first:

```swift
static var databaseURL: URL {
    if let path = ProcessInfo.processInfo.environment["MYAPP_DATABASE"] {
        return URL(filePath: path)
    }
    return .applicationSupportDirectory.appending(path: "MyApp/db.sqlite")
}
```

Read it once, where the path is decided, so nothing can open the real file
first.

**5. The make target.** In the `Makefile`, after the build targets:

```make
# Instruments profiling (app-tooling: instruments-profiling).
PROFILE_BUILD := build-adhoc
include mk/profiling.mk
```

and add `profile` to `help` as the project lists its other targets.

**6. Scenarios the app runs itself.** Recommended, and the user's decision:
it adds a development launch argument to the app. The guide's "Scenarios"
section has the runner. Until then, scenarios can `drive` the app from
outside with `ui-drive` (`focus`, `keys`, `type`, `press`), at the cost the
guide describes.

**7. `AGENTS.md`**: add, where it lists ways of checking the app:

```markdown
* **Performance** is measured, not judged by eye: `make profile` and
  `docs/app-tooling/instruments-profiling/guide.md`. Report main-thread
  delays in Instruments' own categories (Potential Interaction Delay, Brief
  Unresponsiveness, Microhang, Hang), per interaction; only a Hang is a hang.
  Delete traces once their numbers are written down.
```

**8. Record it** in `app-tooling.toml`:

```toml
[patterns.instruments-profiling]
# How the app is pointed at a copy of its data, for the next person to check.
params = { data = "MYAPP_DATABASE" }
```

## Verify

- `make profile` (the `idle` scenario) ends with
  `✓ build/profile/traces/Animation_Hitches-idle-….trace (scenario … s)`.
  Anything else is a failure, and says why. On the first run, a dialog for
  Accessibility or the Instruments password may need the user.
- `lsof` proves the redirect: during a run, `lsof -p <pid> | grep <data file
  name>` shows the copy under `build/profile/data/`, never `REAL_DATA`. (The
  script checks this itself and stops the run if not; this is to see it once.)
- `scripts/trace-query.py delays build/profile/traces/<the trace>` prints a
  `potential-hangs:` line and a `hitches:` line. Missing lines mean the
  template or xctrace version differs: `scripts/trace-query.py tables` lists
  what the trace has.
- `ls $TMPDIR | grep -c 'instruments.*\.ktrace'` is the same before and after a
  run, about a minute after it ends: the staging file was removed.
- One scenario of the project's own, with `make profile SCENARIO=<name>`,
  ends with `✓` and a `.window` file beside the trace.
