# Applying scratch-look

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|scratch-look`.
- **Copied by hand, or the project this came from:** a
  `scripts/make-scratch-icon.py` without this pattern's header, or a
  `ScratchDataBanner` view of the project's own. `diff` them against
  `files/scripts/make-scratch-icon.py` and `swift/ScratchDataBanner.swift`
  (a difference is either a local change that belongs here or an old
  copy). The steps below replace them; peru refuses to overwrite them, so
  delete them first. Keep the generated `AppIcon-Scratch.appiconset`, and
  rerun step 2 over it: with the same script, `git status` then shows it
  unchanged.
- **Something else doing this job.** Look for:
  - a second app icon set (`AppIcon-Debug`, `AppIcon-Dev`, `-Beta`), and
    `ASSETCATALOG_COMPILER_APPICON_NAME` set per configuration (in
    `project.pbxproj`, an `.xcconfig`, `project.yml`, or an `actool
    --app-icon` in a build script);
  - a ribbon, badge or overlay on the icon made by a build phase or a
    tool (a "debug ribbon" script, `badge`);
  - a banner, toolbar item or window title suffix the app shows on test,
    demo or scratch data (search the views for `scratch`, `isScratch`,
    `demo`, `Debug`).

  If any of these exist, describe what the project does and what this
  pattern would do instead to the user, and ask, before changing anything.
- **Not adopted:** a scratch run looks like the real app.

## Parameters

| Parameter | Where to find it |
|---|---|
| The banner's directory | a source directory of the target or module that holds the app's shared UI, and that every window's views can import: for a Swift package, `Sources/<UIModule>/`; for an Xcode app target, a folder of that target. The file is `public`, so it works inside a module |
| The real icon set | the `.appiconset` the app builds with, usually `<App>/Assets.xcassets/AppIcon.appiconset` |
| The scratch build | how the project builds its scratch app: a configuration (`Debug`, `Scratch`), an XcodeGen config, or a build script. Without one, skip step 2: the scratch run is the real build, and gets the banner only |
| The banner's text | what the app already knows about the run: its scratch flag from `scratch-data` (`isScratch`), or a property of the scratch build |

## Steps

The project must already have `pattern-imports` and `scratch-data`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`, with the
banner's directory (ending in `/`) as the third destination:

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
lock, and `ScratchDataBanner.swift` in place. An Xcode target whose folder
is not a synchronized folder needs the Swift file added to it.

**2. The scratch icon.** Make the icon set beside the real one:

```sh
scripts/make-scratch-icon.py MyApp/Assets.xcassets/AppIcon.appiconset \
  MyApp/Assets.xcassets/AppIcon-Scratch.appiconset
```

Look at `icon_1024.png` (or the largest image) in the output, and commit
the set. Then make the scratch build use it, and only the scratch build:

- an `.xcconfig` or build settings of the scratch configuration:
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Scratch`, with a comment
  naming the script, so whoever changes the real icon reruns it;
- XcodeGen: the same setting under that config's `settings`;
- a build script calling `actool`: `--app-icon AppIcon-Scratch` for the
  scratch build.

On iOS, also give the scratch build its own home screen name
(`INFOPLIST_KEY_CFBundleDisplayName = MyApp Scratch`); the Mac's menu bar
keeps `PRODUCT_NAME` whatever this says.

**3. The banner.** Where the app knows whether this run is on scratch data,
give it the text to show, or nil on real data:

```swift
/// What the scratch-data banner says, or nil on the real data.
var scratchDataLabel: String? {
  isScratch ? "MyApp Scratch: scratch data, never synced" : nil
}
```

Apply `.scratchDataBanner(scratchDataLabel)` to the root view of each
window. With a `NavigationSplitView`, apply it to **each column** (the
sidebar, and the detail's root view, with `.frame(maxWidth: .infinity,
maxHeight: .infinity)` so the strip sits at its top), not to the split view:
on macOS 26 the floating sidebar ignores an inset on the window, and the
strip covers its first row. A sheet or second window that shows the data
gets one too.

**4. Formatters.** If the project formats or lints Swift on commit
(swift-format, SwiftLint, a pre-commit hook), exclude the imported Swift
file from it, so it is never rewritten in place. With pre-commit, on the
formatting hook:

```yaml
        exclude: ^Sources/MyAppUI/ScratchDataBanner\.swift$
```

**5. `AGENTS.md`**, beside the `scratch-data` lines:

> A scratch run shows a yellow-and-black caution strip across the top of
> each window, and the scratch build's icon has a caution band. A window
> without the strip is on real data. When the real icon changes, rerun
> `scripts/make-scratch-icon.py` and commit its output.

**6. Record it** in `app-tooling.toml`, with what was filled in:

```toml
[patterns.scratch-look]
params = { banner_dir = "Sources/MyAppUI", icon = "MyApp/Assets.xcassets/AppIcon.appiconset" }
```

## Verify

- `uv lock --script scripts/make-scratch-icon.py --check` exits 0, and the
  script, run as in step 2, ends `✓ <n> images in …` with `n` the number
  of images in the real set.
- Build the scratch app and look at the icon it carries, not the asset
  catalog. Mac: `/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName'
  <App>.app/Contents/Info.plist` prints `AppIcon-Scratch`, and
  `iconutil -c iconset -o /tmp/scratch.iconset
  <App>.app/Contents/Resources/AppIcon-Scratch.icns` exits 0 and writes
  PNGs (`ls -l`: not empty; Xcode puts only a few sizes in the `.icns`, the
  rest in `Assets.car`) that show the band. iOS simulator:
  `plutil -extract CFBundleIcons json -o - <App>.app/Info.plist` names
  `AppIcon-Scratch`, and the bundle's `AppIcon-Scratch60x60@2x.png` shows
  the band. The real build still names `AppIcon`.
- `make run-scratch`, then a screenshot of its window shows the strip
  under the title bar of each column, with the sidebar's first row clear.
  To take one without bringing the app forward: find its window number
  for the pid `pgrep -f` gives (`CGWindowListCopyWindowInfo`, layer 0),
  then `screencapture -x -o -l <window number> scratch.png`.
- `make app-tooling-check` prints `✓ app-tooling imports match peru.yaml`
  after committing, including after a commit that ran the formatter.
