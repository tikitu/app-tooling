# Where a release's notes file goes: not in `dist/`

**Problem.** The starter's Makefile takes `NOTES_FILE` for
`make github-release`, for notes written by hand instead of generated ones,
but says nothing about where to keep the file. FortiMenu (2026-10-02, its
v0.3.0) kept the drafted notes in `dist/release-notes-v0.3.0.md`, which is
ignored and seemed the natural place beside the zip. But `dist:` starts
with `clean`, which deletes `dist/`, so the notes were gone by the time
`make github-release` needed them. They had to be written again. Nothing
warned.

**What worked.** The notes in a scratch directory of the releaser's own,
outside the worktree, and kept nowhere else afterwards: the GitHub release
is where they live. FortiMenu's `docs/releasing.md` says so now
(minddistrict/fortimenu#18).

**Idea.** A starter change: a comment by `NOTES_FILE ?=` in
`starter/Makefile` saying the same, and the same line in the help text for
`github-release`. A patch release: nobody has to act on it. If a releasing
pattern is ever made, it belongs there.
