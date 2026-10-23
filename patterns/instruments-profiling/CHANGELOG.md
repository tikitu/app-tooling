# instruments-profiling changelog

## Unreleased

- **`profile-compare.sh` no longer reports success with nothing recorded.**
  It printed ✓ after every run had been refused. It now exits non-zero when
  any build has no trace of a scenario, says how many runs wrote no trace,
  and stops at the first run `profile-mac.sh` refuses to start (another
  recording, another copy of the app, a nearly full disk), which now exits
  with status 3 for that.
- **A hung recording no longer goes on filling the disk.** The instruments
  service (`DTServiceHub`) of a recorder that hung kept its staging file open
  and went on writing it, 72 GB in six minutes, after the recorder was killed.
  `profile-mac.sh` now stops the service its own xctrace started (noted as
  the recorder's child while it runs; failing that, one that started during
  the run and holds the run's staging file, if no other recording is
  running). A service that was already running is never touched. It also
  gives up waiting for a stop early when the disk falls under
  `MIN_FREE_GB`. With Xcode 27.1 the service holds the file after every run,
  so every run now ends by stopping its own, at once rather than after
  waiting 90 s for it to let go.
- **The light instrument set**: `--instruments "A,B"` on `profile-mac.sh`
  and `profile-compare.sh`, and `INSTRUMENTS=` on `make profile`, add
  instruments to the template. `Blank` with `Hangs,Points of Interest,Time
  Profiler` stages hundreds of megabytes where Animation Hitches stages
  gigabytes, and records no hitches (guide, *Which instrument answers which
  question*).
- **`trace-compare.py` could measure nothing from traces without hitches
  tables**: when exporting the missing table failed (rather than returning
  an empty result, as xctrace 27.1 does), the empty output was parsed as
  XML and the whole trace skipped. `trace-query.py` now treats an export
  that is not XML as a table that is not there.
- **`trace-query.py profile` crashed on a sample with an empty stack.** Such
  samples now count as `(no stack)`.
- Regression tests, run from app-tooling only:
  `patterns/instruments-profiling/tests/run.sh`.

A project that has the pattern: update it; the changes are all in imported
files. A project that worked around a ✓ from `profile-compare.sh` (counting
traces itself) can drop that. If an earlier hung run left a `DTServiceHub`
holding a deleted or large `instruments*.ktrace` (`lsof +L1 | grep ktrace`,
`lsof $TMPDIR/instruments*.ktrace`), and no recording is running, stop that
process to get the space back.

## v0.3.0 (2026-10-20)

`profile-mac.sh`:

- **It says what xctrace launched**, by pid and path, as soon as it starts,
  and stops at once if that is another copy of the app than the one named
  (a stale build with the same bundle id), rather than finding out from the
  trace afterwards and leaving that copy running.
- **It only ever kills the process it launched**, by pid: never a copy
  that was already running (the real app, with `ALLOW_OTHER_COPIES=1`).
- **Staging files no longer leak after a hung recording.** It used to wait
  90 s for the instruments service to close the `instruments*.ktrace` it
  added and then leave it if still open; after a hung stop the service can
  hold it for good, and runs left 10–20 GB each. It now removes them after
  the wait regardless (the space returns when the service lets go), unless
  another recording has started meanwhile. At the start it lists staging
  files earlier runs left, with their total size.

A project that has the pattern: update it. Then look in `$TMPDIR` for
`instruments*.ktrace` files earlier runs left (the next run lists them) and
delete those no process has open (`lsof FILE` prints nothing).

## v0.1.0 (2026-10-05)

First version, from scripts two projects had copied and adapted by hand:
`profile-mac.sh`, `profile-compare.sh`, `trace-query.py`, `trace-compare.py`,
`ui-drive.swift` and `mk/profiling.mk`, with everything app-specific moved
into the project's own `profiling.conf.zsh`. A project with hand-made copies:
follow `apply.md`'s *Detect*, move its settings into `profiling.conf.zsh`,
delete the copies and import.

Tried on one of the two projects, by importing it in place of its own copies
(the other has not been moved over yet): `make profile`, four scenarios
driven from outside (three through accessibility, one with events aimed at
the window), a comparison with a warm-up round, and two failures on purpose.
A config whose redirect pointed the app at the real data was stopped by the
`lsof` check, and neither a successful nor a failed run left a staging file
behind. The in-app scenario runner in the guide is the second project's,
where it is in use; the scripts here have not yet been run there.
