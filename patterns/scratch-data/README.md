# scratch-data

An agent can launch the app, drive it and look at it without ever touching
the real data, because what it launches is **another app**: the scratch
build, "MyApp Scratch", which always opens scratch data. `make run-scratch`
builds and starts it, in the background; `make scratch-reset` throws its
data away.

## The problem

An agent checking a change has to run the app, and the app opens the real
database. Whatever the check does (adds rows, runs a migration, deletes
something to see the empty state) happens to real data. If the app syncs,
it happens to every device. And `open` brings an already running copy to
the front, on whatever data that copy has, so even "launch a fresh build"
is not what it looks like.

A launch flag that switches the real app to scratch data (this pattern's
`--scratch-database`, until it was removed) fails open: launched without it,
by a person, an `open` or another app, the same binary is on real data,
looking exactly like a scratch run. Nobody can tell from the app which one
they have, and an agent that thinks it is on scratch data may delete things.

## What it does

**Scratch is a property of the build, never of a launch.** A scratch build
is its own app:

- named "MyApp Scratch", with bundle id `<real id>.scratch`;
- with an icon carrying the caution band, set when it is built
  ([`scratch-look`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look));
- with the Info.plist key `ScratchBuild = YES`;
- with no iCloud, nor any other entitlement only a provisioning profile
  grants.

A scratch build has no real mode, and a real build has no scratch mode.
Because the bundle id differs, a sandboxed scratch build has a container,
database and user defaults of its own without a line of code; an
unsandboxed one keys its data directory on the bundle id. **The real
build's bundle id, container and data location never change.**

The pattern supplies:

- **`ScratchBuild.swift`**: `ScratchBuild.isScratch`, read from the
  Info.plist key, for the Mac and iOS alike. Every check the app makes
  (the banner, starting sync, a command inbox) uses it.
- **`scripts/make-scratch-app.sh`**, for an app a script bundles
  (`build.sh`): makes the scratch app from the real one, as above, with its
  icon banded by scratch-look's `make-scratch-icon.py`, the entitlements
  made fit for an ad hoc signature (App Groups given `.scratch`), and the
  same done to every app embedded in it (a login item, a menu-bar helper).
  An Xcode app uses a build configuration instead (`apply.md`).
- **`mk/scratch-data.mk`**:
  - **`make run-scratch`**: builds the scratch app, quits the copy of it
    from this checkout if it is running, and launches it behind whatever has
    focus (`open -g`), so it works while someone uses the machine. It
    refuses a bundle without `ScratchBuild = YES`. It quits only processes
    started from this checkout's bundle, by absolute path, each by its pid,
    never by bundle id.
  - **`make scratch-reset`**: quits it and deletes the scratch data
    directory and defaults. It refuses a directory whose path does not name
    the scratch bundle id, so an empty or mistyped variable cannot become
    `rm -rf` of the real data.
  - **`quit-running`** (the real app) and **`scratch-pids`**, for the
    project's own `run` and screenshot targets.

`make run` stays the project's, and is for a person: the real build, in
front.

## iOS: every simulator build is a scratch build

On iOS the test is whether writes can reach real data. On a simulator they
cannot, so every simulator build is a scratch build: through build settings
conditioned on `[sdk=iphonesimulator*]` it gets the key, the name
"MyApp Scratch" and (scratch-look) the banded icon. A device build never
is. `apply.md` has the settings.

## What it asks of a project

- A Mac app built by `make`, by a script (`build.sh`) or `xcodebuild`.
- `ScratchBuild.swift` in a module every check can import, and the app's
  own scratch checks replaced by `ScratchBuild.isScratch` (the steps in
  `apply.md`).
- [`scratch-look`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look),
  for the icon (`make-scratch-app.sh` needs its script).
- `AGENTS.md` telling agents to use `make run-scratch`, never `make run`.

## A scratch build never launches anything that defaults to real data

A scratch build starts only scratch builds: its own embedded helpers
(which `make-scratch-app.sh`, or the scratch configuration, makes scratch
too), never the real helper by its path or bundle id. Code that names a
helper's bundle id derives it from the app's own
(`Bundle.main.bundleIdentifier`), so the scratch app names the scratch
helper. Each helper reads `ScratchBuild.isScratch` from its own Info.plist:
nothing travels in launch arguments, which a sandboxed app cannot pass on
anyway (`NSWorkspace.OpenConfiguration.arguments` is silently ignored when
the caller is sandboxed).

## What it does not do

- **No seed data.** The scratch database starts empty. A project that wants
  a copy of real data in it writes that target itself, copying from a
  backup, never the live file.
- **URL schemes and document types are copied as they are.** A scratch
  build registers the same ones as the real app, and Launch Services may
  pick either to open a link or a document.
- **It is not the guarantee against syncing.** The scratch build has no
  iCloud entitlement and does not start sync, but for an app that syncs the
  guarantee is that agents' builds are not entitled to sync at all:
  [`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration).
