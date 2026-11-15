# scratch-look changelog

## v0.10.0 (2026-11-15)

**Breaking, with scratch-data: what is marked is the scratch build ("MyApp
Scratch", its own app), and every mark is fixed when it is built.**

- **`ScratchDockIcon` is removed.** A scratch build's icon is banded when
  it is built, so nothing is drawn at run time, and nothing can be banded
  twice. A project that called `ScratchDockIcon.apply(isScratch:)`: delete
  the call (`make app-tooling-update` deletes the file), and drop the file
  from any formatter or lint exclusion.
- **`make-scratch-icon.py` also reads an `.iconset`** (what `iconutil -c
  iconset` makes of an `.icns`), which is how scratch-data's
  `make-scratch-app.sh` bands the icon of an app a script bundles. Nothing
  to do for an asset catalog project.
- **New `ScratchMenuBarBadge.swift`**, imported beside the banner by the
  same `scratch-look-swift` rule: `ScratchMenuBarBadge.image { mark }`, a
  caution badge with "SCRATCH" for a menu-bar app's icon. A project with a
  menu-bar app (`MenuBarExtra`, a status item): show it in the scratch build
  (`apply.md` step 4) and delete its own badge. Every project: extend
  formatter and lint exclusions to the new file (step 5); it has an
  `#if os(macOS)`, which a rule forbidding platform conditionals in a shared
  module must ignore.
- **The strip no longer fills the title bar.** `ScratchDataBanner`'s yellow
  stayed behind the strip only in its own frame, not the top safe area
  under a macOS toolbar. Arrives with the update.
- **The banner's condition is `ScratchBuild.isScratch`** (scratch-data),
  not a launch flag. Take scratch-data's update first, then replace the
  banner's condition (step 3).
- **Every scratch build has a banded icon**: on the Mac through the scratch
  configuration's `AppIcon-Scratch` or `make-scratch-app.sh`, on iOS
  through `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=iphonesimulator*]` (step
  2). A project whose scratch builds had no icon of their own: add it.
- **`apply.md` step 5 covers lint rules too**, not only formatters: an
  imported file cannot carry the project's ignore comments, so a rule that
  would flag it ignores it in its own configuration.
- Update the `AGENTS.md` lines (step 6), and verify both builds side by
  side (Verify).

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
