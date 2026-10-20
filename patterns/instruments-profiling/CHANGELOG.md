# instruments-profiling changelog

## Unreleased

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
