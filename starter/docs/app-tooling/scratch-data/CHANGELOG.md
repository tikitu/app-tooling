# scratch-data changelog

## Unreleased

**Fix: an iOS target with no display name of its own got an empty one on
device builds.** v0.10.0's `INFOPLIST_KEY_CFBundleDisplayName[sdk=iphonesimulator*]`
gives every other SDK `CFBundleDisplayName = ""` when the target has no
unconditional display name and a generated Info.plist: the device build
(TestFlight included) and any Mac build of the same target. `apply.md`
step 3 now says to set the unconditional one to the real name, and Verify
checks the device build's name. A project that followed v0.10.0 with an
iOS app: build for a device (`-destination 'generic/platform=iOS'`, each
configuration that ships) and run `plutil -extract CFBundleDisplayName raw`
on its `Info.plist`. If it prints nothing, add
`INFOPLIST_KEY_CFBundleDisplayName = MyApp` (the real name) to the app
target, and check again. Projects whose target already had a display name
(XcodeGen with one in `settings.base`, say) have nothing to do.

## v0.10.0 (2026-11-15)

**Breaking: scratch is a separate build, "MyApp Scratch", never a launch
flag. `--scratch-database` is removed.** A scratch build is its own app:
bundle id `<id>.scratch`, the name "MyApp Scratch", an icon banded when it
is built (scratch-look), the Info.plist key `ScratchBuild = YES`, and no
iCloud. It always opens scratch data; the real build never does. On iOS,
every simulator build is a scratch build; a device build never is. The
real build's bundle id, container and data location do not change.

New:

- **`ScratchBuild.swift`**, imported by a new third rule
  (`scratch-data-swift`) into a directory the project chooses:
  `ScratchBuild.isScratch` reads the key, on the Mac and iOS.
- **`scripts/make-scratch-app.sh <MyApp.app> <MyApp Scratch.app>`**, for an
  app a script bundles: makes the scratch app from the real one (id, name,
  key, banded icon, entitlements fit for ad hoc, ad hoc signature), embedded
  helper apps included. Needs scratch-look's `make-scratch-icon.py`. It
  refuses app extensions, XPC services and apps inside frameworks (not
  supported yet), and an asset-catalog icon. It stops, rather than sign
  without entitlements (which would drop the sandbox), when a signed
  bundle's entitlements cannot be read.
- **`mk/scratch-data.mk`:** new parameter `SCRATCH_APP` (the scratch
  bundle); `SCRATCH_BUILD` is now required and builds it; `run-scratch`
  launches it without `--scratch-database`, and refuses a bundle without
  `ScratchBuild = YES`; `scratch-reset` now requires `SCRATCH_DIR` to be
  under the scratch bundle id (a path component ending `.scratch`) rather
  than to have "scratch" in its last component, and `SCRATCH_DEFAULTS`
  (when set) to end `.scratch`; quitting also reaches the bundle's embedded
  helpers; `APP` is only used by
  `quit-running`; new `quit-scratch` and `scratch-pids`.

A project that has the pattern, in this order (`apply.md` has each step):

1. `make app-tooling-update`, then add the `scratch-data-swift` import and
   rule to `peru.yaml` (step 1) and sync.
2. Make the scratch build (step 3): for a `build.sh` app a `build-scratch`
   target calling `scripts/make-scratch-app.sh`; for an Xcode app a
   configuration with the `.scratch` bundle id, "MyApp Scratch",
   `IS_SCRATCH_BUILD = YES` and entitlements without iCloud; on iOS the
   `[sdk=iphonesimulator*]` settings. Take scratch-look's update with it
   (the icon).
3. In the app (step 2): remove `--scratch-database` and every other scratch
   check of its own, and use `ScratchBuild.isScratch`. A sandboxed app
   drops its scratch database path and defaults suite: the container is
   its own. **An unsandboxed app keys its data directory on the bundle id
   for the scratch build, without moving the real build's data**: if the
   real directory is not already named by the bundle id, the real build
   keeps its name. **Every App Group id and shared defaults suite named in
   code gets `.scratch` in the scratch build** (unsandboxed, the
   entitlements do not stop `UserDefaults(suiteName: "<group>")` reaching
   the real build's data); the real build's ids stay as they are. Code
   naming a helper's bundle id derives it from the app's own.
4. In the `Makefile` (step 4): set `SCRATCH_APP` and `SCRATCH_BUILD`, move
   `SCRATCH_DIR` and `SCRATCH_DEFAULTS` to the scratch bundle id's
   locations, and take `--scratch-database` out of anything else that
   passed it (`profile`, `run-adhoc`).
5. Exclude `ScratchBuild.swift` from formatters and lint rules (step 5).
6. Rewrite the `AGENTS.md` lines (step 6) and record `swift_dir` in
   `app-tooling.toml`.
7. Verify as `apply.md` says: both builds side by side (name, bundle id,
   icon, key), and the scratch build on scratch data only. Anything that
   changes where data lives is tested on a scratch copy, never on the real
   data.

## v0.6.0 (2026-10-24)

**A sandboxed app cannot pass `--scratch-database`, or any argument, to an
app it launches.** `NSWorkspace.OpenConfiguration.arguments` and
`.environment` are ignored when the launching app is sandboxed, silently,
so a helper or second app launched from a scratch run with a scratch flag
starts on real data. The README has a new section on it. A project that has
the pattern: take the update, and check that the app never launches another
app or helper whose default is real data while on scratch data; if it does,
start the helper's scratch copy from the terminal instead and have the app
only signal it (the README says how).

**`SCRATCH_ARGS`: more launch arguments for `run-scratch`**, given before
`--scratch-database` (AppKit would take the argument after a lone switch as
its value). For a project that passes the app more on a scratch run, such as
`command-inbox`'s `--commands <dir>`. Nothing to do unless the project wants
it; one that worked around its absence (its own `run-scratch` beside the
fragment's) can set `SCRATCH_ARGS` before the include instead.

## v0.3.0 (2026-10-20)

**`quit-running` could quit the real app.** It found the app with
`pgrep -f "$(APP)/Contents/MacOS/"`, which for a relative `APP` (such as
`build/MyApp.app`) also matches the real app running from another checkout
of the project, and then quit it by bundle id, which reaches the real app
from any checkout. It now quits only processes whose command line starts
with this checkout's absolute `$(APP)`, each by its pid, and never uses the
bundle id. `BUNDLE_ID` is no longer a parameter of the fragment.

A project that has the pattern: update it (`make app-tooling-update`).
Nothing else is required. If it worked around this (for instance
`run-scratch scratch-reset: APP := $(CURDIR)/$(APP)` and
`run-scratch scratch-reset: BUNDLE_ID :=` before the include), delete those
lines and the deviation recorded in `app-tooling.toml`. A project with its
own `quit-running` (made from the starter, or copied) has the same hazard:
replace it with the fragment's (`apply.md`), or copy the fragment's version.

## v0.2.0 (2026-10-20)

First version: `mk/scratch-data.mk`, with `make run-scratch` and
`make scratch-reset`, from the starter's targets. `scratch-reset` now
refuses a `SCRATCH_DIR` whose name does not contain `scratch`. A project
with its own copies of these targets (any made from the starter): follow
`apply.md`, delete its `run-scratch`, `scratch-reset` and `quit-running`,
and include the fragment with its parameters.
