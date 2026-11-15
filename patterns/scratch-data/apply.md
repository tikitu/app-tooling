# Applying scratch-data

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted, before the scratch build** (`peru.yaml` imports
  `app-tooling|scratch-data` but not `scratch-data-swift`, or the app reads
  `--scratch-database`): follow every step below. Step 2 says what to
  remove.
- **Already adopted:** `peru.yaml` imports `app-tooling|scratch-data-swift`.
- **Copied by hand:** the `Makefile` has its own `run-scratch` and
  `scratch-reset` targets (projects made from the starter before this
  pattern, and those that copied them). The steps replace them, and a
  `quit-running` macro of the project's own, since the fragment defines it.
- **Something else doing this job.** Look for:
  - a launch argument or environment variable that picks another database
    (`--scratch`, `--demo`, `--database`, a `UserDefaults` argument);
  - checks of the simulator (`SIMULATOR_UDID`, `SIMULATOR_DEVICE_NAME`,
    `targetEnvironment(simulator)`) that decide what data is used;
  - an Info.plist key of the project's own that marks a variant
    (`MyAppVariant`, `MyAppSyncEnabled` read as "scratch");
  - a separate scheme, configuration or bundle id for a test copy of the
    app;
  - `run-adhoc`, `run-test` or similar targets, and what data they open.

  If any of these exist, describe what the project does and what this
  pattern would do instead to the user, and ask, before changing anything.
- **Not adopted:** the app opens one database, whoever launches it.

## Parameters

| Parameter | Where to find it |
|---|---|
| `APP` | the real build's bundle, usually `build/<App>.app` |
| `BUNDLE_ID` | the real Mac app's bundle id: `Resources/Info.plist`, `build.sh`, the `Makefile` or the Xcode target. Not a parameter of the fragment; the paths below use it. The scratch build's is `$(BUNDLE_ID).scratch` |
| `SCRATCH_APP` | where the scratch build is made: `build/<App> Scratch.app` beside `$(APP)` for a `build.sh` app; the scratch configuration's product for an Xcode app |
| `SCRATCH_BUILD` | the target that makes `$(SCRATCH_APP)` (step 3) |
| `SCRATCH_DIR` | the scratch build's data directory, as the app's code finds it (step 2). Sandboxed: `$(HOME)/Library/Containers/$(BUNDLE_ID).scratch/Data/Library/Application Support/<dir>`. Unsandboxed: `$(HOME)/Library/Application Support/$(BUNDLE_ID).scratch` |
| `SCRATCH_DEFAULTS` | the scratch build's defaults. Sandboxed: `$(HOME)/Library/Containers/$(BUNDLE_ID).scratch/Data/Library/Preferences/$(BUNDLE_ID).scratch`. Unsandboxed: `$(BUNDLE_ID).scratch`. Empty if the app has no settings |
| `SCRATCH_ARGS` | launch arguments for the scratch build, each with a value, such as `--commands <dir>` for [`command-inbox`](https://github.com/tikitu/app-tooling/tree/main/patterns/command-inbox). Usually empty. Never a mode switch: the build decides what is scratch |
| The Swift directory | a source directory of a module that everything checking for scratch can import (usually the one holding the database code): for a Swift package, `Sources/<Module>/`; for an Xcode app target, a folder of that target. `ScratchBuild` is `public` |

Whether the app is sandboxed: `com.apple.security.app-sandbox` in its
entitlements.

## Steps

The project must already have `pattern-imports`, and should take
[`scratch-look`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look)
with this (a `build.sh` app needs its icon script).

**1. Import the pattern.** In `peru.yaml`, under `imports:`, with the Swift
directory (ending in `/`) as the third destination:

```yaml
    app-tooling|scratch-data: ./
    app-tooling|scratch-data-docs: docs/app-tooling/scratch-data/
    app-tooling|scratch-data-swift: Sources/MyAppCore/
```

and beside the other rules:

```yaml
rule scratch-data:
    export: patterns/scratch-data/files
rule scratch-data-docs:
    pick: [patterns/scratch-data/README.md, patterns/scratch-data/apply.md, patterns/scratch-data/CHANGELOG.md]
    export: patterns/scratch-data
rule scratch-data-swift:
    export: patterns/scratch-data/swift
```

Then `uvx peru@1.3.5 sync`, which puts `mk/scratch-data.mk`,
`scripts/make-scratch-app.sh` and `ScratchBuild.swift` in place. If the
project has its own `run-scratch`, delete it and its `scratch-reset` and
`quit-running` first (step 4), or `make` will warn about overridden recipes.
An Xcode target whose folder is not a synchronized folder needs the Swift
file added to it.

**2. The app's code.** Wherever the app asks "is this scratch?", it asks
`ScratchBuild.isScratch`, and nothing else:

- **Remove `--scratch-database`** and every other way the app decides it is
  on scratch data (Detect, above): a `static let isScratch =
  CommandLine.arguments.contains(…)`, simulator checks, variant keys.
  Callers that took an `isScratch` argument can keep it, given
  `ScratchBuild.isScratch`.
- **The database:** one path for both builds, as the real build has always
  had it. **The real build's location must not change.**
  - Sandboxed: nothing to do. The scratch build's container is its own, so
    the same path is somewhere else. Delete the scratch branch that opened a
    file under `URL.temporaryDirectory`.
  - Unsandboxed: key the directory on the bundle id, without moving the
    real build's data. If the real directory is already named by the bundle
    id, nothing to do. Otherwise keep its name for the real build:

    ```swift
    /// The real build keeps the directory it always had; a scratch build's
    /// is named by its bundle id (`<id>.scratch`), so they never share data.
    let name = ScratchBuild.isScratch ? Bundle.main.bundleIdentifier ?? "MyApp.scratch" : "MyApp"
    let directory = URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory)
    ```

    Anything else the app writes outside a container (caches, logs, files at
    fixed paths) is keyed the same way.
- **User defaults:** the standard ones. The scratch build's domain is its
  own bundle id, so delete a `UserDefaults(suiteName: "<id>.scratch")` and
  `.defaultAppStorage` that only existed for scratch runs.
- **App Groups and defaults suites named in code.** The scratch build's
  entitlements give each App Group `.scratch` (step 3), but nothing holds
  an **unsandboxed** app to its entitlements: a hard-coded
  `UserDefaults(suiteName: "group.com.example.MyApp")`, `containerURL(forSecurityApplicationGroupIdentifier:)`
  or `~/Library/Group Containers/…` path in the scratch build opens the
  real build's data. Name each group id and shared suite in one place,
  with `.scratch` added in the scratch build, matching its entitlements.
  The real build's ids stay as they are:

  ```swift
  /// The real build's App Group, unchanged; the scratch build's ends
  /// ".scratch", as its entitlements do, so they never share data.
  let appGroup = "group.com.example.MyApp" + (ScratchBuild.isScratch ? ".scratch" : "")
  ```

  Helpers use the same (the scratch build sets `ScratchBuild` in them
  too). Sandboxed apps should do it as well: it costs nothing and keeps
  the code honest if the sandbox is ever dropped.
- **Sync:** when `ScratchBuild.isScratch`, do not start it. Put the
  condition where sync is started, so it is visible at launch.
- **Helpers:** a scratch build launches only its own embedded helpers, and
  names a helper's bundle id by deriving it from its own (README).

The starter's `Mac app entrypoint.swift` and `Core/Schema.swift`
(<https://github.com/tikitu/app-tooling/tree/main/starter/Packages>) are a
worked example of a sandboxed app.

**3. The scratch build.**

- **An app a script bundles (`build.sh`):** a target that makes the scratch
  app from the real one:

  ```make
  SCRATCH_APP := build/MyApp Scratch.app
  build-scratch: build
  	scripts/make-scratch-app.sh "$(APP)" "$(SCRATCH_APP)"
  ```

  For an app that syncs, `build` must be one that cannot
  ([`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration)):
  the script drops iCloud entitlements, but builds from an ad hoc base.
- **An Xcode app (Mac):** a configuration of its own (`Scratch`, or
  `Debug` if that is already the agents' build), with an xcconfig:

  ```
  // Configurations/Scratch.xcconfig — the scratch build (app-tooling: scratch-data)
  PRODUCT_BUNDLE_IDENTIFIER = com.example.MyApp.scratch
  PRODUCT_NAME = MyApp Scratch
  PRODUCT_MODULE_NAME = MyApp
  IS_SCRATCH_BUILD = YES
  CODE_SIGN_ENTITLEMENTS = MyApp/MyApp-Scratch.entitlements
  ```

  The entitlements file has no iCloud, and any App Group ends `.scratch`.
  `PRODUCT_MODULE_NAME` keeps `import MyApp` in tests working. Set
  `IS_SCRATCH_BUILD = NO` at the project level, and add the key to the
  target's Info.plist file (Xcode merges it into a generated one;
  `INFOPLIST_KEY_` does not take keys of a project's own):

  ```xml
  <key>ScratchBuild</key>
  <string>$(IS_SCRATCH_BUILD)</string>
  ```

  `SCRATCH_BUILD` is then an `xcodebuild -configuration Scratch` target, and
  `SCRATCH_APP` its product.
- **iOS** (every simulator build, any configuration), on the app target, and
  on each app extension that reads the key:

  ```
  IS_SCRATCH_BUILD[sdk=iphonesimulator*] = YES
  INFOPLIST_KEY_CFBundleDisplayName[sdk=iphonesimulator*] = MyApp Scratch
  ```

  with the same Info.plist entry. XcodeGen: the same keys under the
  target's `settings.base`, and `ScratchBuild: $(IS_SCRATCH_BUILD)` under
  `info.properties`. The icon is scratch-look's step 2.

**4. The Makefile.** Set the parameters and include the fragment, after the
target that builds the scratch app:

```make
# The scratch build (app-tooling: scratch-data): `make run-scratch`,
# `make scratch-reset`. docs/app-tooling/scratch-data/.
SCRATCH_BUILD    := build-scratch
SCRATCH_DIR      := $(HOME)/Library/Containers/$(BUNDLE_ID).scratch/Data/Library/Application Support/MyApp
SCRATCH_DEFAULTS := $(HOME)/Library/Containers/$(BUNDLE_ID).scratch/Data/Library/Preferences/$(BUNDLE_ID).scratch
include mk/scratch-data.mk
```

Add `run-scratch` and `scratch-reset` to `help`. The project's own `run`
targets can use `$(quit-running)` before `open`, and a screenshot target
`$(scratch-pids)` to find the scratch app's process.

**5. Formatters and linters.** If the project formats or lints Swift
(swift-format, SwiftLint, ast-grep rules, a pre-commit hook), exclude the
imported `ScratchBuild.swift` from it, as scratch-look's `apply.md` step 5
says: an imported file cannot carry the project's ignore comments, and a
reformatted one fails `make app-tooling-check`.

**6. `AGENTS.md`**, where it says how to run the app:

> Run the Mac app with `make run-scratch`, never `make run`: it builds and
> launches, in the background, the scratch build "MyApp Scratch" (bundle id
> `<id>.scratch`), a separate app that only ever opens scratch data and
> never syncs. `make scratch-reset` throws that data away. On iOS, every
> simulator build is a scratch build; a device build never is.

**7. Record it** in `app-tooling.toml`:

```toml
[patterns.scratch-data]
params = { swift_dir = "Sources/MyAppCore" }
```

## Verify

- Build both apps, and compare them: `plutil -extract CFBundleIdentifier
  raw`, `CFBundleName` and `ScratchBuild` of each `Contents/Info.plist`.
  The real build has its old bundle id and no `ScratchBuild` (the extract
  fails); the scratch build has `<id>.scratch`, "MyApp Scratch" and `true`
  (or `YES`). `codesign -d --entitlements - --xml` of the scratch build has
  no `com.apple.developer.` key.
- `make -n run-scratch` prints the build, then `open -g -n "<SCRATCH_APP>"`
  with `SCRATCH_ARGS`, and no `--scratch-database`.
- `make run-scratch SCRATCH_APP=<the real build>` refuses: `✗ … is not a
  scratch build`.
- `make scratch-reset SCRATCH_DIR=/tmp/MyApp` exits non-zero with
  `✗ SCRATCH_DIR ('/tmp/MyApp') must be under the scratch bundle id`.
- `make run-scratch`, then `pgrep -fl "<App> Scratch.app/Contents/MacOS/"`
  shows the process, and `ls "<SCRATCH_DIR>"` shows its database. Run this
  only once step 2 is in, and for an app that syncs, only with a base build
  that cannot.
- If the real app is running, `pgrep -fl "<App>.app/Contents/MacOS/"` shows
  the same pid for it before and after `make run-scratch` and
  `make scratch-reset`, and the real data's modification time is unchanged.
- `make scratch-reset`; then `ls "<SCRATCH_DIR>"` fails with "No such file
  or directory".
- iOS: a simulator build's `Info.plist` has `ScratchBuild` `YES` and the
  display name "MyApp Scratch"; a device build (`-destination
  'generic/platform=iOS'`) has neither.
