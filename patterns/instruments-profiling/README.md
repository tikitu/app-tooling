# instruments-profiling

An agent can't feel whether an app is slow. With this pattern it can measure
it: record Instruments traces of the Mac app with no one at the keyboard,
read them as text, and show with numbers whether a change made the app
smoother. It covers main-thread delays as Instruments categorises them,
late frames, where CPU time goes, why SwiftUI views update, and memory.

It is two apps' worth of experience packaged. In both, the traces found
problems nobody had noticed (a computed property that re-read a whole log on
every click, a tree that laid out every node to draw a few), and in both a
comparison of builds showed what each fix was worth, and once, that a fix
had made something else slower.

## What it prevents

Profiling unattended goes wrong in ways that look like success:

- **The real data reaches the profiled app.** An `.app` given to xctrace is
  resolved by bundle id, and once launched another checkout's signed build,
  which then synced the copy of the data it had been handed. The script
  launches the executable itself, refuses builds that can sync, copies the
  data, and checks with `lsof` that the app does not have the real file open.
- **The numbers are of something else.** Another copy of the app running, a
  recording left over, the screen of the accessibility driver itself, or a
  scenario starting from wherever the app was left. The script refuses to
  run beside other copies and recordings, scenarios run inside the app
  where possible, and the trace's process is checked by pid.
- **The disk fills.** xctrace never removes its multi-gigabyte staging files;
  a day left 529 GB. The script removes its own and refuses to start with
  little room.
- **A comparison is noise.** Builds are recorded in turn on frozen data,
  with a warm-up round, and compared by medians with their ranges.

## What it asks of a project

- A Mac app built from the command line, and a way to build a variant that
  cannot sync (ad hoc, without iCloud entitlements).
- A way to point the app at other data: an environment variable or launch
  argument. Most apps need one added.
- A `profiling.conf.zsh` of its own: the app, the data, the scenarios.
- Ideally, scenarios the app runs itself behind a development launch
  argument (a few lines; the guide has them). Scenarios can be driven from
  outside instead, at some cost to accuracy.
- Xcode 26 or later, `sqlite3`, `zsh`, the system `python3`. Nothing to
  install.
- From the user, once: Developer Mode, Accessibility for the terminal or
  agent host, and a password for the Allocations and Leaks templates
  (cached ~10 hours).

It requires [`pattern-imports`](https://github.com/tikitu/app-tooling/tree/main/patterns/pattern-imports).

## What it brings

```
scripts/profile-mac.sh       record a template while a scenario runs, safely
scripts/profile-compare.sh   record several builds in turn, for before/after
scripts/trace-query.py       read a trace: delays, profile, SwiftUI, memory
scripts/trace-compare.py     medians per build and scenario
scripts/ui-drive.swift       post scrolls, trackpad drags and keys; accessibility
mk/profiling.mk              make profile TEMPLATE=… SCENARIO=…
```

and [`guide.md`](guide.md): which template answers which question, how to
read the results (in Instruments' own terms), the comparison method, and the
traps.

## What it does not do

- **iOS devices.** The guide says what works on the simulator and what needs
  a phone; the scripts drive the Mac app only.
- **Fix anything.** It finds and measures.
- **CI.** Recording takes the screen over and needs the permissions above.
  It is for an agent working on the user's Mac.

## The skill

[`skill/SKILL.md`](https://github.com/tikitu/app-tooling/tree/main/patterns/instruments-profiling/skill/SKILL.md) is a short Claude Code skill that makes an
agent reach for this when asked about performance, and points it at the
guide imported into the project. It lives here so that it changes with the
pattern. To install it from a local checkout of app-tooling:

```sh
ln -s ~/code/app-tooling/patterns/instruments-profiling/skill ~/.claude/skills/instruments-profiling
```
