# scratch-look changelog

## v0.9.0 (2026-11-14)

- **Expected of every app that has `scratch-data`** (README). Nothing to
  do for a project that has it. One that has `scratch-data` without it:
  adopt it, or record it under `[declined.scratch-look]` with the reason.

- **The Dock icon of a scratch run on the Mac gets the caution band.** New
  `ScratchDockIcon.swift`, imported beside `ScratchDataBanner.swift` by the
  same `scratch-look-swift` rule: `ScratchDockIcon.apply(isScratch:)`, called
  at launch, draws the band over the app's own icon and makes that the Dock
  icon. It does nothing on real data, or when the build's icon is already
  a scratch set (an icon name ending `-Scratch`). A project with the
  pattern: `make app-tooling-update`; call
  `ScratchDockIcon.apply(isScratch: isScratch)` at launch (`apply.md`,
  step 4), on a Mac target that has a Dock icon; extend any formatter
  exclusion to the new file (step 5); add the Dock icon to the
  `AGENTS.md` lines (step 6); and check it with a Dock screenshot of a
  scratch run (Verify).

## v0.6.0 (2026-10-24)

First version: `scripts/make-scratch-icon.py` (with its lock), which
derives a scratch icon set with a caution band from the real one, and
`ScratchDataBanner.swift`, a caution strip across the top of windows on
scratch data, imported into a directory the project chooses. To adopt:
follow `apply.md`. A project with its own copies of these (the one they
came from): delete them, import the pattern, and keep its generated icon
set.
