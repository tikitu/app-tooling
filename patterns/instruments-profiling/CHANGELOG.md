# instruments-profiling changelog

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
