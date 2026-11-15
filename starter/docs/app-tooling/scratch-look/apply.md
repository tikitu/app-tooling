# Applying scratch-look

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|scratch-look`.
- **Adopted with the Dock icon** (`ScratchDockIcon.apply(isScratch:)` is
  called at launch; v0.9.0): it is gone, since a scratch build's icon is now
  banded when it is built. Update the imports, delete the call, and drop
  `ScratchDockIcon.swift` from any formatter or lint exclusion (step 5).
- **Copied by hand, or the project this came from:** a
  `scripts/make-scratch-icon.py` without this pattern's header, or a
  `ScratchDataBanner` view of the project's own. `diff` them against
  `files/scripts/make-scratch-icon.py` and `swift/ScratchDataBanner.swift`
  (a difference is either a local change that belongs here or an old
  copy). The steps below replace them; peru refuses to overwrite them, so
  delete them first. Keep the generated `AppIcon-Scratch.appiconset`, and
  rerun step 2 over it: with the same script, `git status` then shows it
  unchanged.
- **A menu-bar badge of the project's own** (a "SCRATCH" image drawn for a
  `MenuBarExtra` or status item): step 4 replaces it.
- **Something else doing this job.** Look for:
  - a second app icon set (`AppIcon-Debug`, `AppIcon-Dev`, `-Beta`), and
    `ASSETCATALOG_COMPILER_APPICON_NAME` set per configuration (in
    `project.pbxproj`, an `.xcconfig`, `project.yml`, or an `actool
    --app-icon` in a build script);
  - a ribbon, badge or overlay on the icon made by a build phase or a
    tool (a "debug ribbon" script, `badge`), or a banded `.icns` a script
    makes;
  - code that sets `applicationIconImage` or a Dock tile on scratch data;
  - a banner, toolbar item or window title suffix the app shows on test,
    demo or scratch data (search the views for `scratch`, `isScratch`,
    `demo`, `Debug`).

  If any of these exist, describe what the project does and what this
  pattern would do instead to the user, and ask, before changing anything.
- **Not adopted:** a scratch build looks like the real app.

## Parameters

| Parameter | Where to find it |
|---|---|
| The Swift directory | a source directory of the target or module that holds the app's shared UI, and that every window's views can import: for a Swift package, `Sources/<UIModule>/`; for an Xcode app target, a folder of that target. The files are `public`, so they work inside a module |
| The real icon set | an asset catalog app: the `.appiconset` it builds with, usually `<App>/Assets.xcassets/AppIcon.appiconset`. An app a script bundles: none (its `.icns` is banded by `make-scratch-app.sh`) |
| The scratch build | scratch-data's: a configuration, the `[sdk=iphonesimulator*]` settings on iOS, or `make-scratch-app.sh` |
| The banner's text | what the scratch build is: usually "MyApp Scratch: scratch data, never synced" |

## Steps

The project must already have `pattern-imports` and `scratch-data`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`, with the Swift
directory (ending in `/`) as the third destination:

```yaml
    app-tooling|scratch-look: ./
    app-tooling|scratch-look-docs: docs/app-tooling/scratch-look/
    app-tooling|scratch-look-swift: Sources/MyAppUI/
```

and beside the other rules:

```yaml
rule scratch-look:
    export: patterns/scratch-look/files
rule scratch-look-docs:
    pick: [patterns/scratch-look/README.md, patterns/scratch-look/apply.md, patterns/scratch-look/CHANGELOG.md]
    export: patterns/scratch-look
rule scratch-look-swift:
    export: patterns/scratch-look/swift
```

Then `uvx peru@1.3.5 sync`, which puts `scripts/make-scratch-icon.py`, its
lock, `ScratchDataBanner.swift` and `ScratchMenuBarBadge.swift` in place.
An Xcode target whose folder is not a synchronized folder needs the Swift
files added to it. `ScratchMenuBarBadge.swift` compiles to nothing outside
macOS, so a shared iOS and Mac module can hold it.

**2. The scratch icon.**

- **An app a script bundles:** nothing to do: `make-scratch-app.sh`
  (scratch-data) bands the `.icns` of every scratch build with this script.
- **An asset catalog:** make the icon set beside the real one:

  ```sh
  scripts/make-scratch-icon.py MyApp/Assets.xcassets/AppIcon.appiconset \
    MyApp/Assets.xcassets/AppIcon-Scratch.appiconset
  ```

  Look at `icon_1024.png` (or the largest image) in the output, and commit
  the set. Then make the scratch build use it, and only the scratch build,
  with a comment naming the script, so whoever changes the real icon reruns
  it:
  - the Mac scratch configuration's xcconfig:
    `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Scratch`;
  - iOS, on the app target in every configuration:
    `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=iphonesimulator*] = AppIcon-Scratch`;
  - XcodeGen: the same settings in `project.yml`;
  - a build script calling `actool`: `--app-icon AppIcon-Scratch` for the
    scratch build.

  A project that generates its icon sets in the build (git-ignored) runs
  the script there instead, after the real set is made.

**3. The banner.** Give it the text to show, or nil in the real build:

```swift
/// What the scratch-data banner says, or nil in the real build.
var scratchDataLabel: String? {
  ScratchBuild.isScratch ? "MyApp Scratch: scratch data, never synced" : nil
}
```

Apply `.scratchDataBanner(scratchDataLabel)` to the root view of each
window. With a `NavigationSplitView`, apply it to **each column** (the
sidebar, and the detail's root view, with `.frame(maxWidth: .infinity,
maxHeight: .infinity)` so the strip sits at its top), not to the split view:
on macOS 26 the floating sidebar ignores an inset on the window, and the
strip covers its first row. A sheet or second window that shows the data
gets one too.

**4. The menu-bar badge** (a Mac app with a `MenuBarExtra` or status item).
In a scratch build, show the badge instead of the plain mark:

```swift
MenuBarExtra {
  MyAppMenu(model: model)
} label: {
  if ScratchBuild.isScratch {
    Image(nsImage: ScratchMenuBarBadge.image { MyAppMark() })
      .accessibilityLabel("MyApp Scratch")
  } else {
    MyAppMark().accessibilityLabel("MyApp")
  }
}
```

`mark` is the glyph the real menu-bar icon shows, at menu-bar size; the
badge draws it in black. Delete a badge of the project's own.

**5. Formatters and linters.** If the project formats or lints Swift
(swift-format, SwiftLint, ast-grep rules, a pre-commit hook), exclude the
imported Swift files from it, so they are never rewritten in place or
flagged for what the project's own code may not do. An imported file cannot
carry the project's ignore comments. With pre-commit, on the formatting
hook:

```yaml
        exclude: ^Sources/MyAppUI/Scratch(DataBanner|MenuBarBadge)\.swift$
```

A rule that forbids `#if os(…)` in a shared module (the badge has one)
ignores the file in the rule's own configuration: ast-grep's `ignores:` in
the rule file, SwiftLint's `excluded:`. A formatter run over a directory
gets a file list without them (`find … -not -name 'Scratch*.swift'`).

**6. `AGENTS.md`**, beside the `scratch-data` lines:

> The scratch build "MyApp Scratch" has a caution band on its icon, a
> yellow-and-black caution strip across the top of each window (and, for a
> menu-bar app, a SCRATCH badge in the menu bar). A window without the
> strip is the real app, on real data. When the real icon changes, rerun
> `scripts/make-scratch-icon.py` and commit its output.

**7. Record it** in `app-tooling.toml`, with what was filled in:

```toml
[patterns.scratch-look]
params = { banner_dir = "Sources/MyAppUI", icon = "MyApp/Assets.xcassets/AppIcon.appiconset" }
```

## Verify

- `uv lock --script scripts/make-scratch-icon.py --check` exits 0, and the
  script, run as in step 2, ends `✓ <n> images in …` with `n` the number
  of images in the real set.
- Build the real and the scratch app, and look at the icon each carries,
  not the asset catalog. An `.icns` (`CFBundleIconFile`):
  `iconutil -c iconset -o /tmp/scratch.iconset
  "<App> Scratch.app/Contents/Resources/AppIcon.icns"` exits 0 and writes
  PNGs (`ls -l`: not empty) that show the band; the real build's do not. An
  asset catalog on the Mac: `/usr/libexec/PlistBuddy -c 'Print
  :CFBundleIconName' <App>.app/Contents/Info.plist` prints `AppIcon-Scratch`
  for the scratch build and `AppIcon` for the real one, and the
  `AppIcon-Scratch.icns` in its Resources shows the band. iOS simulator:
  `plutil -extract CFBundleIcons json -o - <App>.app/Info.plist` names
  `AppIcon-Scratch`, and the bundle's `AppIcon-Scratch60x60@2x.png` shows
  the band; a device build names `AppIcon`.
- `make run-scratch`, then a screenshot of its window shows the strip
  under the title bar of each column, with the title bar itself not yellow
  and the sidebar's first row clear. To take one without bringing the app
  forward: find its window number for the pid `pgrep -f` gives
  (`CGWindowListCopyWindowInfo`, layer 0), then `screencapture -x -o -l
  <window number> scratch.png`.
- A menu-bar app: with the scratch build running, a capture of the menu
  bar (`screencapture -x -R 0,0,<screen width>,40 menubar.png`; the screen
  must be unlocked) shows the badge. On a locked screen, render
  `ScratchMenuBarBadge.image` in a test or preview and look at that.
- `make app-tooling-check` prints `✓ app-tooling imports match peru.yaml`
  after committing, including after a commit that ran the formatter.
