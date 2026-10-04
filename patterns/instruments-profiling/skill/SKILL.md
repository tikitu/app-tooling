---
name: instruments-profiling
description: Measure a Mac (or iOS) app's performance with Instruments, headlessly — main-thread delays, hitches, where CPU time goes, why SwiftUI views update, memory — and show whether a change helped. Use when asked whether an app is slow, laggy, janky or using too much memory, to profile it, to find what to optimise, or to compare builds before and after a fix.
---

# Profiling with Instruments

Performance is measured, not judged from the code. This skill is a pointer:
the method, the scripts and their safety checks are the app-tooling pattern
`instruments-profiling`.

## Find the pattern

- **The project has it** (`docs/app-tooling/instruments-profiling/` exists):
  read `guide.md` there before recording anything, and use the project's
  `make profile`, `scripts/profile-mac.sh`, `scripts/trace-query.py` and
  `scripts/profile-compare.sh`. The app's settings and scenarios are in
  `profiling.conf.zsh`.
- **It does not:** offer to apply it. The instructions are
  `patterns/instruments-profiling/apply.md` in app-tooling
  (https://github.com/tikitu/app-tooling, or a local checkout), and need the
  project to take `pattern-imports` first. Applying it is the user's decision.
- **There is something else** (hand-copied `profile-mac.sh` and friends,
  `xctrace` in the Makefile): the pattern's `apply.md`, *Detect*, says what to
  do. Do not add a second set beside the first.

## Rules that hold before you have read anything else

- **Never profile on the real data**, and never with a build that can sync:
  a copy of real data in a syncing build gets uploaded. The pattern's
  recorder copies the data and refuses syncing builds; if you record by hand,
  do the same.
- **Launch the executable inside the bundle**, not the `.app`: xctrace
  resolves an `.app` by bundle id and can launch another copy.
- **Ask before recording Network**: it captures all HTTP traffic on the Mac,
  unencrypted, credentials included.
- **Say what Instruments says.** Main-thread delays are *Potential Interaction
  Delay*, *Brief Unresponsiveness*, *Microhang* or *Hang*; only a Hang is a
  hang. Report per interaction (counts per category, typical and longest
  delay), never a total summed over a scenario.
- **Compare builds, don't eyeball one.** Interleaved rounds on frozen data,
  a warm-up round, medians with ranges (`profile-compare.sh`,
  `trace-compare.py`).
- **Clean up.** xctrace leaves multi-gigabyte `instruments*.ktrace` files in
  `$TMPDIR` (the pattern's recorder removes its own); traces are disposable
  once their numbers are written down.
