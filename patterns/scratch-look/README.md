# scratch-look

A run on scratch data looks different from the real app: a caution band on
the scratch build's icon, and a caution strip across the top of its
windows. Requires
[`scratch-data`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-data).

## The problem

With a scratch copy of an app and the real one on the same machine, only
the name told them apart, and on the Mac not even that: Xcode always sets
`CFBundleName` from `PRODUCT_NAME`, so the menu bar of a scratch build says
the same as the real app's. The Dock, the app switcher and the window
itself were identical. A person, or an agent reading a screenshot, could
not tell which data they were looking at, and the cost of guessing wrong is
working on the real data while thinking it is scratch.

## What it does

Two pieces, in the same yellow and black, so each points at the other:

- **`scripts/make-scratch-icon.py`** derives a scratch icon set from any
  `.appiconset`: a copy with a caution band across the lower right corner of
  every image, "SCRATCH" on it from 128 px up, and thicker below that so it
  still reads in a menu or a small Dock tile. It is run once by hand, and
  again when the real icon changes; its output is committed, and the build
  does not run it. The scratch build uses that set as its app icon
  (`ASSETCATALOG_COMPILER_APPICON_NAME`). It needs `uv`; Pillow is pinned in
  the script and locked in `scripts/make-scratch-icon.py.lock`, and the
  script runs with `--locked`, so it refuses to run if the two disagree.
- **`ScratchDataBanner.swift`**: a SwiftUI strip, `.scratchDataBanner(text)`,
  which shows `text` across the top of a view, or nothing when `text` is
  nil. It says less in a narrow column (`ViewThatFits`), keeps the whole
  text for VoiceOver, and has fixed colours, the same in light and dark. It
  is self-contained (SwiftUI only), and goes into a directory the project
  chooses, inside whichever target or module holds its shared UI. The app
  decides when it shows: on a scratch build, and on a `--scratch-database`
  run.

## What it asks of a project

- `scratch-data`, and `uv` (`brew install uv`) to make the icon.
- For the icon: a scratch **build** (its own configuration, bundle id or
  build script) whose app icon can be set apart from the real one's.
- For the banner: a place for one Swift file, and a value the app already
  knows (is this a scratch run?) to pass to it. On the Mac with
  `NavigationSplitView`, one modifier per column.
- If the project formats or lints Swift on commit, the imported Swift file
  excluded from it: a reformatted imported file fails `make
  app-tooling-check`.

## What it does not do

- **No icon for a scratch run of the real build.** `--scratch-database` on
  its own runs the same binary as the real app, with the same icon; such a
  run gets the banner only. (A Mac app could set its Dock icon at launch;
  the pattern does not.)
- **It does not decide what is scratch.** The banner shows whatever text it
  is given; the app's own scratch flag (from `scratch-data`, or its scratch
  build) supplies it.
- It is a marker, not a guard. What keeps a scratch run off real data is
  `scratch-data` and, for an app that syncs,
  [`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration).
