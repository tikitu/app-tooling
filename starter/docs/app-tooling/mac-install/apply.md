# Applying mac-install

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|mac-install`.
- **Copied by hand:** the `Makefile` has its own `install` target. Projects
  made from the starter before this pattern have one that does
  `cp -R "$(APP)" /Applications/` and `lsregister -f`; others `ditto`, quit
  the app first, or set a date as the build number. The step below replaces
  it. Keep anything it does that this does not (a check on the built app
  before installing it) in the target that builds it, `MAC_INSTALL_BUILD`.
- **Something else doing this job.** Look for:
  - `ditto`, `cp -R` or `rsync` into `/Applications` in the `Makefile` or a
    script;
  - `lsregister` anywhere;
  - `CURRENT_PROJECT_VERSION=` on an `xcodebuild` command line, or a
    `CFBundleVersion` written by `build.sh` or a build phase.

  If the project installs some other way (an installer package, a Homebrew
  cask of its own), describe it to the user, and ask, before changing
  anything.
- **Not adopted:** the app is copied into `/Applications` by hand, or run
  only from its build directory.

## Parameters

| Parameter | Where to find it |
|---|---|
| `MAC_INSTALL_APP` | the built bundle to install: the `Makefile`'s `APP` for a SwiftPM app, usually `build/<App>.app`; for Xcode, `$(DERIVED_DATA)/Build/Products/Release/<App>.app` or wherever the project's `-derivedDataPath` puts the configuration it installs |
| `MAC_INSTALL_BUNDLE_ID` | the Mac app's bundle id: `Resources/Info.plist`, `build.sh`, `project.yml` or the `Makefile` |
| `MAC_INSTALL_BUILD` | the target that builds `MAC_INSTALL_APP`, with the build number below. Which configuration to install (Debug, Release, one that syncs) is the project's; for an app with `sync-configuration`, a target that builds and checks the production app |
| `MAC_INSTALL_DIR` | only to install somewhere other than `/Applications` |

## Steps

The project must already have `pattern-imports`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|mac-install: ./
    app-tooling|mac-install-docs: docs/app-tooling/mac-install/
```

and beside the other rules:

```yaml
rule mac-install:
    export: patterns/mac-install/files
rule mac-install-docs:
    pick: [patterns/mac-install/README.md, patterns/mac-install/apply.md, patterns/mac-install/CHANGELOG.md]
    export: patterns/mac-install
```

Then `uvx peru@1.3.5 sync`, which puts `mk/mac-install.mk` and the two
scripts in place.

**2. The `Makefile`.** Delete the project's own `install` target (and its
`.PHONY` entry). Then, after the variables it uses are defined:

```make
# `make install`: the Mac app into /Applications with a rising build
# number, quitting and restarting a running copy (app-tooling: mac-install).
# docs/app-tooling/mac-install/.
MAC_INSTALL_APP       := build/MyApp.app
MAC_INSTALL_BUNDLE_ID := com.example.MyApp
MAC_INSTALL_BUILD     := build-release
include mk/mac-install.mk
```

`MAC_INSTALL_BUILD` must be set before the `include`.

**3. The build number.** The target named by `MAC_INSTALL_BUILD` must give
the app `$(MAC_INSTALL_BUILD_NUMBER)` as its `CFBundleVersion`.

- **Xcode:** add `CURRENT_PROJECT_VERSION=$(MAC_INSTALL_BUILD_NUMBER)` to
  its `xcodebuild` line. The `Info.plist` must read
  `$(CURRENT_PROJECT_VERSION)` for `CFBundleVersion`, as Xcode's templates
  and XcodeGen's defaults do; check, since a literal there ignores it.
- **`build.sh`:** pass it in the environment,
  `BUILD_NUMBER="$(MAC_INSTALL_BUILD_NUMBER)" ./build.sh release`, and have
  `build.sh` use it when set: `BUILD_NUMBER="${BUILD_NUMBER:-…}"`, with
  whatever it computed before after the `:-`.

If that target is also the everyday build, passing the number there too is
harmless: every build then gets the time it was made.

**4. `AGENTS.md`.** Where it describes installing or running the real app,
add:

```markdown
- `make install` puts the app in /Applications (for a person: it replaces
  the real app). If the Dock shows an old icon afterwards, follow
  docs/app-tooling/mac-install/README.md, "When the old icon stays"; its
  last step needs sudo and is the user's.
```

## Verify

Into a scratch directory, never `/Applications` without the user's say-so:

```sh
D=$(mktemp -d)
make install MAC_INSTALL_DIR=$D            # 1
make install MAC_INSTALL_DIR=$D            # 2
plutil -extract CFBundleVersion raw $D/MyApp.app/Contents/Info.plist
open -g $D/MyApp.app; sleep 3
make install MAC_INSTALL_DIR=$D            # 3
make mac-stale-registrations MAC_INSTALL_DIR=$D
```

- **1** ends `✓ installed …/MyApp.app, build <yyyymmddhhmmss>`. A build
  number that is not today's date means step 3 did not take.
- **2** prints no `⚠ build … is not above` warning: each `make` gets a new
  number. A warning here means the build is not using it.
- **3** prints `✓ quit the running …` and `✓ started it again`, and
  `pgrep -lf "$D/MyApp.app"` then shows one new pid.
- **`mac-stale-registrations`** prints `✓ …/MyApp.app is registered` and
  either a list or `✓ no other registrations`. It exits 1 if
  `lsregister -dump` printed nothing; an empty list on exit 0 is real.

Then clean up: quit the app,
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u $D/MyApp.app`
and `rm -rf $D`.
