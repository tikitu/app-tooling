# Profiling with Instruments, headlessly: the guide

How an agent records Instruments traces of a Mac app with no one at the
keyboard, reads them, and shows whether a change helped. [`README.md`](README.md)
says what the pattern is for; [`apply.md`](apply.md) sets a project up. This
page is for using it.

Worked out on two apps with Xcode 27 / xctrace 27 on macOS 26: a table of
~11,000 rows with search, and a SwiftUI tree of ~830 nodes in a two-way scroll
view. Both had real problems that these traces found and that their fixes
were measured against.

## The shape of it

```sh
make profile TEMPLATE="Animation Hitches" SCENARIO=search   # record
scripts/trace-query.py delays <trace>                        # what it felt like
scripts/trace-query.py profile <trace> --main-thread         # where the time went
scripts/trace-query.py swiftui <trace> --module MyApp        # why views updated
scripts/profile-compare.sh --data <frozen copy> --warmup \
  before=<one build> after=<another>                         # did the change help
scripts/trace-compare.py build/profile/compare --builds before,after
```

`profile-mac.sh` records any template against a re-signed copy of the app and
a copy of its data, while the app runs a scenario, and checks afterwards which
process it traced. `trace-query.py` turns `xctrace export` XML into summaries.
`profile-compare.sh` records several builds in turn; `trace-compare.py` gives
medians.

## Safety: real data

A profiling run launches the app many times, unattended, often from a build
that is not the one in daily use. Each rule here is in the script because its
absence went wrong once.

1. **Never the real data.** The app gets a fresh copy (`sqlite3 .backup` by
   default), pointed at by an environment variable or launch argument, and
   once it is running `lsof` must show it does not have the real file open.
   If the app has no way to be pointed at other data, add one before
   profiling (a launch argument read only in development is enough).
2. **Never a build that can sync.** Given a copy of real data, it would
   upload it, and its sync engine would treat the copy as a new device. The
   script refuses a build whose entitlements match `REFUSE_ENTITLEMENTS`
   (iCloud by default). Build an ad-hoc, unentitled variant for profiling.
3. **Launch the executable, not the bundle.** `xctrace --launch -- My.app`
   resolves the bundle through LaunchServices by bundle id, which can pick a
   different copy: another checkout's signed build, in the case that taught
   this. The script launches `My.app/Contents/MacOS/<exe>`.
4. **Check what was traced, by pid.** The trace's table of contents names
   the launched process; look its path up by that pid. Templates such as
   Animation Hitches list every process on the Mac, including any other
   running copy of the same app.
5. **Find your own processes by an anchored path**, or by `$!`: `pgrep -f
   name` also matches the shell running the command.
6. **The simulator build can sync too.** An iOS simulator build carries its
   entitlements in a binary section, CloudKit included, and syncs on any
   simulator signed into iCloud. Profile on a simulator with no Apple
   Account.

## One-time setup

| What | Needed for | How to check, how to get it |
|---|---|---|
| Developer Mode | everything | `DevToolsSecurity -status` |
| The Instruments authorization right | Allocations, Leaks | a password dialog on first use, cached ~10 hours (`security authorizationdb read com.apple.dt.instruments.process.analysis`, `timeout`). Headless, the recording waits with the app suspended; `--start-timeout` reports it. A restart clears it |
| `get-task-allow` on the target | Allocations, Leaks, `heap`, `leaks`, `malloc_history` | the script adds it to a copy of the app, keeping the app's own entitlements |
| Accessibility for the process that runs the scripts | `ui-drive` (keys, accessibility) | System Settings → Privacy & Security → Accessibility; a Swift one-liner printing `AXIsProcessTrusted()` checks it |
| Posting events | `ui-drive` scrolling and trackpad | `CGPreflightPostEventAccess()` |
| Processor Trace | the Processor Trace template | System Settings → Privacy & Security → Developer Tools |

Network is a template like the others, but it captures **all HTTP traffic on
the Mac, unencrypted**, into the trace and the system log, credentials
included. It is off unless the user opts in for the session
(`--allow-network`). It is rarely what a performance question needs.

## Which instrument answers which question

| Template | Mac | iOS simulator | Tells you |
|---|---|---|---|
| Animation Hitches | ✓ | ✗ | every late frame with Instruments' reason; the Hangs instrument's main-thread delays; a Time Profiler. **The default**: small, quick to read |
| Time Profiler | ✓ | ✓ | where CPU time went, symbolicated |
| SwiftUI | ✓ | ✗ (records, empty) | each view body update with duration and severity, and the cause graph: what changed to make each view update. Big and slow to read: one short scenario at a time |
| Allocations, Leaks | ✓ | ✓ | live and transient memory per type, every allocation's backtrace, leaks. Need the password |
| Swift Concurrency, File Activity, System Trace, App Launch, Logging | ✓ | not tried | tasks and actors; syscalls with paths; thread states; launch; os_log |
| Processor Trace | ✓ | – | every call with exact duration, instructions and cycles, for **one second** (the template's limit), 1–2 GB a run |
| Data Persistence | Core Data only | – | nothing for SQLite |
| Power Profiler | ✗ | – | iOS hardware only |

A device is needed for SwiftUI and hitch data on iOS. On a phone the app is
usually the real one, on real data: observe it, but run nothing that edits.

Cost: an Animation Hitches trace of 15 s is tens of MB and reads back in
seconds. A SwiftUI trace of 15 s is ~500 MB and took six minutes and ~19 GB
of memory to summarise; a 30 s one did not finish in twenty minutes.
Allocations over 30 s of use was 2 GB.

## The configuration: `profiling.conf.zsh`

The project's own file, sourced by the scripts. `apply.md` has an example to
start from.

| Key | Meaning | Default |
|---|---|---|
| `APP_BUNDLE` | the `.app` to profile, relative to the repository root | required |
| `BUILD_HINT` | what to say when it is missing | |
| `REAL_DATA` | the file the app normally reads; empty if it has none | |
| `DATA_NAME` | the copy's file name | `REAL_DATA`'s |
| `copy_data SRC DST` | a function making the copy | `sqlite3 SRC ".backup 'DST'"` |
| `describe_data FILE` | a function printing what the copy holds | its size |
| `LAUNCH_ENV` | `VAR=value` pairs; `{DATA}` is the copy | |
| `LAUNCH_ARGS` | arguments; `{DATA}` is the copy | |
| `REFUSE_ENTITLEMENTS` | an extended regex; a build whose entitlements match is refused | `icloud\|ubiquity` |
| `ALLOW_OTHER_COPIES` | `1` to record while another copy of the app runs (the real one, in daily use) | `0` |
| `MIN_FREE_GB` | refuse below this | `10` |
| `SETTLE_SECONDS` | for scenarios the app does not announce: how long after launch they start | `2` |
| `SCENARIO_NOTIFY_PREFIX` | the Darwin notification prefix the app's own scenarios post | |
| `COMPARE_SCENARIOS` | `profile-compare.sh`'s default scenarios | `(idle)` |
| `scenario_NAME` | a function per scenario (below) | |

## Scenarios

A scenario is what the app does while it is recorded. Two rules matter more
than any other in this method:

- **The app should drive itself.** Driving it through the accessibility API
  put a third of the measured main-thread time into answering the driver,
  and once a client connects, SwiftUI keeps an accessibility tree up to date
  besides. A development launch argument (`--scenario NAME`) that runs the
  steps in the app avoids both.
- **It starts from a known state.** A scenario that begins wherever the app
  happens to be (a scroll position, a selection, a window size) does
  different work each run. Launch into a fixed state, and check it once
  (a screenshot by window id) before trusting a comparison.

A `scenario_NAME` function in `profiling.conf.zsh` sets:

- `scenario_args=(…)`: launch arguments for this scenario;
- `scenario_notifies=1` if the app posts `$SCENARIO_NOTIFY_PREFIX.started`
  when it begins and `.done` when it ends;
- optionally a function `drive`, run once the scenario has started, with
  `$PID` and `$DRIVER` (the compiled `ui-drive`).

```zsh
SCENARIO_NOTIFY_PREFIX=com.example.myapp.scenario
scenario_select()  { scenario_args=(--scenario select); scenario_notifies=1; }
scenario_scroll()  { scenario_args=(--scenario wait); scenario_notifies=1
                     drive() { $DRIVER scroll-window $PID --lines -8 --times 120; }; }
scenario_search()  { drive() { $DRIVER focus $PID AXTextField 0; $DRIVER type $PID "milk"; }; }
```

The recorder writes the scenario's stretch of the trace (`since until`, in
seconds) to a `.window` file beside it, which `trace-compare.py` reads, so
launch is left out of every number. Without notifications the stretch starts
`SETTLE_SECONDS` after launch.

In the app, the runner is a few lines. It waits until the app has its data,
posts `.started`, does each step inside a Points of Interest signpost
interval (so the steps show in every template), and posts `.done`:

```swift
import OSLog
import notify

private let signposter = OSSignposter(subsystem: "com.example.myapp", category: .pointsOfInterest)

enum ProfilingScenario: String {
    case select, wait
    static let prefix = "com.example.myapp.scenario"

    @MainActor func run(on model: AppModel) async {
        while !model.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(1))
        notify_post("\(Self.prefix).started")
        switch self {
        case .select:
            for item in model.items.prefix(8) {
                await step("select") { model.selection = item.id }
            }
        case .wait: break   // the script drives: scrolling
        }
        notify_post("\(Self.prefix).done")
    }

    @MainActor private func step(_ name: StaticString, _ action: () -> Void) async {
        let state = signposter.beginInterval(name)
        action()
        try? await Task.sleep(for: .milliseconds(1500))
        signposter.endInterval(name, state)
    }
}
```

Started from the app's entry point when `--scenario` is given, and compiled
into development builds only if the project prefers. An app with a command
inbox (the starter's) can take its steps from there instead.

Scrolling still needs posted events. `ui-drive scroll-window` aims at the
app's largest window by the window server's bounds, which asks the app
nothing; `ui-drive trackpad` posts continuous pixel scrolls with gesture and
momentum phases, which is a different code path from wheel steps. Both move
the pointer and take the screen over: run them only when no one is using the
Mac. Accessibility commands (`tree`, `press`, `focus`, `keys`, `type`) remain
for what nothing else reaches; `tree` caps its walk, because a table's
children are all its rows and an uncapped walk of 11,000 tied the app up for
minutes.

## Reading the numbers

**Main-thread delays: use Instruments' words.** The Hangs instrument reports
every main-thread delay over ~33 ms and files each under its own category:
*Potential Interaction Delay* (shorter), *Brief Unresponsiveness* (roughly
100–250 ms), *Microhang* (250 ms and over) and *Hang* (longer still). Only
the last is what Apple calls a hang; say "delay" for the others. Report per
interaction (how many in each category, the typical and the longest), not a
total over the scenario: fourteen clicks of 100 ms each read as "1.4 s hung"
when summed, which is alarming and wrong.

**Hitches** are late frames, with Instruments' reason ("expensive app
update", "expensive render"). For scrolling, judge by **frames shown** and
total late-frame time, and only between runs that move the same distance:
main-thread time hardly moves when scrolling improves, because the time
saved goes into drawing more frames.

**Profiles**: `profile --main-thread` gives total and self time per function;
`--binary MyApp` attributes framework time to the app's innermost frame,
which says which of its calls caused it. Read the whole stack too: in one app
its own code was a few percent of the time, and the rest was SwiftUI's
graph updates, layout and hit testing.

**SwiftUI**: `swiftui --module MyApp` (the binary's name) gives each of the
app's views' body updates, the longest updates with their root cause, and
the edges into them: `@Observable AppModel.selection -> DetailView.body`
says which property invalidated which view.

**Memory**: `memory` gives live and transient bytes per type and leaks by
responsible frame. `malloc_history PID ADDRESS`, on an app launched with
`MallocStackLogging=1`, gives one live object's allocation backtrace: the
quickest way from "there are 10,917 of these" to a file and line. `footprint`,
`vmmap --summary`, `heap`, `leaks` and `leaks --outputGraph` all work without
Instruments.

**Release or debug**: profile what will be run. A release build profiles the
same way (it keeps its symbols unless stripped); in a SwiftUI app it may be
only modestly faster than debug, since most of the time is in system
frameworks that are optimised either way.

## Did the change help?

```sh
git worktree add --detach build/wt-before main
git worktree add build/wt-after my-branch
(cd build/wt-before && make build); (cd build/wt-after && make build)
sqlite3 <real data> ".backup 'build/profile/frozen/data.sqlite'"
scripts/profile-compare.sh --data build/profile/frozen/data.sqlite --warmup \
  before=build/wt-before/build/MyApp.app after=build/wt-after/build/MyApp.app
scripts/trace-compare.py build/profile/compare --builds before,after -f 'Body=MyView.body.getter'
```

- **Interleave.** Each round runs every scenario on every build in turn, so
  a busy minute on the machine lands on all of them.
- **Freeze the data.** One copy for every run: the real data grows while
  you measure.
- **Warm up.** An unrecorded first round: content fetched or cached on first
  use otherwise makes the first round different. It took one app's spread
  from ±15% to 1–2%.
- **Three rounds or more; medians with ranges.** If the ranges overlap,
  there is no result.
- **Build worktrees inside the project's `build/`** if the code audit tool
  must reach them; delete them afterwards.

To find what is worth fixing before designing a fix:

- **Upper-bound builds.** A throwaway build that removes a suspect outright
  (no images, no animation, no hit testing) shows what fixing it could be
  worth. Most suspects are worth little; the few that are point at the fix.
- **Scale the input.** The same scenario on a tenth of the data says whether
  the cost grows with the data or is fixed per interaction. In one app a
  sidebar switch cost ~45 ms whatever the row count; in another, per-frame
  cost grew with the number of views, which pointed at drawing fewer.
- **Check the fix is not a regression elsewhere.** A first version of a
  search fix was correct and doubled the cost of a filter with no text in
  it; only the comparison showed it.
- **Say what a fix does not touch.** Delays that move from Brief
  Unresponsiveness to Potential Interaction Delay are a real improvement,
  and still delays.

Traces measure how much; tests check still correct. A fix that caches needs
tests holding it to the old answers.

## Profiling a test run

A Swift Testing or XCTest bundle runs under `xctest`, so xctrace can launch
it and stops when it exits:

```sh
xcrun xctrace record --template 'Time Profiler' --no-prompt --output t.trace \
  --launch -- "$(xcrun -f xctest)" .build/…/MyTests.xctest
```

Selecting one Swift Testing test this way does not work (`-XCTest` filters
XCTest only); give performance tests a target of their own, or gate them on
an environment variable passed with `--env`. Wrap the code under study in
`OSSignposter` intervals: Points of Interest are recorded by every template.

## Traps

Each of these looked like something else first.

- **xctrace leaves its staging files.** Every recording stages a
  multi-gigabyte `instruments*.ktrace` in `$TMPDIR` and never removes it; a
  day of profiling left 529 GB and a nearly full disk. The saved `.trace` does
  not need it. `profile-mac.sh` removes its own once the instruments service
  lets go (~45 s). To clear older ones: move those over an hour old that no
  process has open (`lsof`) into a folder, check a saved trace still opens,
  then delete the folder.
- **xctrace can hang at "Stopping recording…"** for good, occasionally;
  the target may then ignore SIGTERM. The script gives up after
  `--stop-timeout` (time spent saving does not count), kills both, and waits
  for the recorder to release the kperf lock, without which the next run
  fails with "could not lock kperf".
- **Headless dialogs wait forever.** The Allocations password, and Network's
  terminal prompt (which `--no-prompt` accepts).
- **xctrace ignores SIGTERM while recording**; SIGINT stops and saves.
- **Exit status 54** with a saved trace is the normal end of a run whose
  target was killed at the time limit.
- **Export can be enormous.** Read big traces by streaming (`trace-query.py`
  does); past 2 GB of XML, a whole-document parser fails.
- **Other copies distort the numbers silently**: a forgotten debug copy, a
  hung recording's target. The script refuses to start beside them.
- **A full disk fails oddly**: silent exits, other tools' services going
  away. The script refuses below `MIN_FREE_GB`. Keep the numbers in a text
  file and delete traces once a comparison is written up.
- **Accessibility walks** of a large table tie up both processes for
  minutes: cap them.

## Versions

Table and column names (`potential-hangs`, `hang-type`, `hitches`,
`hitches-frame-lifetimes`, `swiftui-updates`, `swiftui-causes`,
`time-profile`), the delay categories, and the formatted values the scripts
parse (`"37.22 ms"`, `"00:04.440.920"`, `"Main Thread"`) are xctrace 27's. A
new Xcode can rename them; when a command finds no table, run `trace-query.py
tables TRACE` and compare before trusting an empty answer.
