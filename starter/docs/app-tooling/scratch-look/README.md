# scratch-look

A scratch build looks different from the real app: a caution band on its
icon, a caution strip across the top of its windows, and on a menu-bar app
a caution badge in the menu bar. Requires
[`scratch-data`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-data),
whose scratch build ("MyApp Scratch", its own app) is what it marks.

**Expected of every app that has `scratch-data`.** Agents leave scratch
apps open, and without it nobody can tell those windows from the real
app's. A project that does not take it declines it in its
`app-tooling.toml`, with the reason:

```toml
[declined.scratch-look]
as_of = "v0.9.0"   # the release it was declined against
reason = "…"
```

## The problem

With a scratch copy of an app and the real one on the same machine, only
the name told them apart, and on the Mac not even that: Xcode always sets
`CFBundleName` from `PRODUCT_NAME`, so the menu bar of a scratch build said
the same as the real app's. The Dock, the app switcher and the window
itself were identical. A person deciding which copy to delete, or an agent
reading a screenshot, could not tell which data they were looking at, and
the cost of guessing wrong is working on the real data while thinking it is
scratch.

## What it does

Every piece is in the same yellow and black, so each points at the others,
and every piece is fixed when the app is built: a scratch build always
looks like one, and a real build never does.

- **`scripts/make-scratch-icon.py`** derives a scratch icon set from any
  `.appiconset` or `.iconset`: a copy with a caution band across the lower
  right corner of every image, "SCRATCH" on it from 128 px up, and thicker
  below that so it still reads in a menu or a small Dock tile. For an asset
  catalog it is run by hand, and again when the real icon changes; its
  output is committed, and the scratch build uses it as its app icon
  (`ASSETCATALOG_COMPILER_APPICON_NAME`). For an app a script bundles,
  scratch-data's `make-scratch-app.sh` runs it over the `.icns` of every
  scratch build. It needs `uv`; Pillow is pinned in the script and locked
  in `scripts/make-scratch-icon.py.lock`, and the script runs with
  `--locked`, so it refuses to run if the two disagree.
- **`ScratchDataBanner.swift`**: a SwiftUI strip, `.scratchDataBanner(text)`,
  which shows `text` across the top of a view, or nothing when `text` is
  nil. It says less in a narrow column (`ViewThatFits`), keeps the whole
  text for VoiceOver, and has fixed colours, the same in light and dark.
  SwiftUI only. The app shows it when `ScratchBuild.isScratch`
  (scratch-data).
- **`ScratchMenuBarBadge.swift`**, Mac only: `ScratchMenuBarBadge.image
  { mark }`, the app's menu-bar mark beside "SCRATCH" on a caution badge,
  as an image for a `MenuBarExtra` label or a status item. A menu-bar app
  (`LSUIElement`) has no Dock icon and often no window, so this is where it
  shows. It compiles to nothing outside macOS.

The Swift files go into a directory the project chooses, inside whichever
target or module holds its shared UI; the badge uses the banner's colours,
so they go together.

## What it asks of a project

- `scratch-data`'s scratch build, and `uv` (`brew install uv`) for the icon.
- For the banner and the badge: a place for two Swift files. On the Mac
  with `NavigationSplitView`, one modifier per column.
- If the project formats or lints Swift, the imported Swift files excluded
  from it: a reformatted imported file fails `make app-tooling-check`, and
  an imported file cannot carry the project's ignore comments.

## What it does not do

- **It does not decide what is scratch.** The banner shows whatever text it
  is given; `ScratchBuild.isScratch` (scratch-data) supplies it.
- **Nothing is drawn at run time.** The icon is the build's own, so it is
  the same in Finder, Launchpad, the Dock and the app switcher, and nothing
  can be banded twice.
- It is a marker, not a guard. What keeps a scratch build off real data is
  `scratch-data` and, for an app that syncs,
  [`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration).
