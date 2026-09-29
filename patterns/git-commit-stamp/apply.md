# Applying git-commit-stamp

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `scripts/stamp-git-commit.sh` exists, and
  `app-tooling.toml` has `[patterns.git-commit-stamp]`. To update, follow
  `CHANGELOG.md` from the recorded release or commit (`patterns/README.md`
  says how for each); `diff` the project's scripts
  against `files/scripts/` to see what copying them again would change.
- **Something else doing this job.** Look for:
  - a run-script phase in `project.yml` (`preBuildScripts`,
    `postCompileScripts`, `postBuildScripts`) that calls `git`, `PlistBuddy`
    or `plutil`;
  - `git rev-parse` or `git describe` in `build.sh` or the `Makefile`;
  - an `Info.plist` key holding a commit, under any name;
  - `CURRENT_PROJECT_VERSION` computed rather than a literal, or
    `agvtool` in the Makefile.

  If any of these exist, describe what the project does and what this
  pattern would do instead to the user, and ask, before changing anything.
- **Not adopted:** `project.yml` sets `CURRENT_PROJECT_VERSION` to a literal
  (usually `1`) and nothing writes a commit. `build.sh` stamps
  `CFBundleVersion` from the date. That is the usual starting point; the
  date stamp is left alone (see step 4).

## Parameters

| Parameter | Where to find it |
|---|---|
| Path from `project.yml` to `scripts/` | `project.yml`'s directory relative to the repo root; `apps/ios/` gives `$SRCROOT/../../scripts` |
| iOS app target | the `type: application` target under `targets:` in `project.yml` |
| Device and bundle id make variables | the Makefile's `ios-device-run` target: usually `IOS_DEVICE`, and a bundle id variable or the literal in `project.yml` |
| Mac bundle's plist | in `build.sh`, the `Info.plist` path the bundle is assembled with, typically `"$APP/Contents/Info.plist"` |

A project without an iOS app skips steps 2 and 3; one without a `build.sh`
skips step 4.

## Steps

**1. Copy the scripts** from `files/scripts/` to `scripts/`, keeping them
executable. `device-which-commit.sh` only if the project has an iOS app.

**2. Add the build phase** to the iOS app target in `project.yml`, beside
its `dependencies:`:

```yaml
    # Record the commit in the built app (app-tooling: git-commit-stamp).
    # On the built plist, after Xcode has written it and before signing.
    postBuildScripts:
      - name: Stamp git commit
        script: '"$SRCROOT/../../scripts/stamp-git-commit.sh" --bundle-version "$TARGET_BUILD_DIR/$INFOPLIST_PATH"'
        inputFiles:
          - $(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)
        basedOnDependencyAnalysis: false
```

- `inputFiles` makes Xcode run the phase after the plist is written.
- `basedOnDependencyAnalysis: false` runs it on every build, since a commit
  changes nothing Xcode tracks. Xcode prints a note saying so on each build;
  that is expected.
- Leave `CURRENT_PROJECT_VERSION` as it is. The phase overwrites the built
  value; the literal is what an unstamped build would say.

Then `make ios-project` to regenerate.

**3. Add the Makefile target**, beside `ios-device-run`, and to `.PHONY` and
`help` as the project does for other targets:

```make
# Which commit the app on $(IOS_DEVICE) was built from (app-tooling:
# git-commit-stamp).
ios-device-which:
	@scripts/device-which-commit.sh '$(IOS_DEVICE)' '<bundle id>'
```

**4. Stamp the Mac app**, if there is a `build.sh`: after the bundle's
`Info.plist` is written and before `codesign`:

```bash
# Which commit this is, for `plutil -extract AppGitCommit raw …/Info.plist`.
# Before signing, so the signature covers it (app-tooling: git-commit-stamp).
scripts/stamp-git-commit.sh "$APP/Contents/Info.plist"
```

Without `--bundle-version`: the Mac bundle can be read directly, so it keeps
whatever `CFBundleVersion` scheme it has.

**5. Show it in the app.** Suggest this to the user rather than choosing a
place for it:

```swift
extension Bundle {
    /// The commit this build came from, written by scripts/stamp-git-commit.sh.
    public var gitCommit: String {
        object(forInfoDictionaryKey: "AppGitCommit") as? String ?? "unstamped"
    }
}
```

Usual places: a line at the foot of settings on iOS; on the Mac,
`orderFrontStandardAboutPanel(options: [.version: Bundle.main.gitCommit])`.
Logging it once at launch through `Logger` also makes it findable in
`/usr/bin/log show`.

**6. Update `AGENTS.md`**: where it describes installing on a device, add
that `make ios-device-which` says which commit is installed. Where it
describes the Mac build, that
`plutil -extract AppGitCommit raw <app>/Contents/Info.plist` says which
commit a bundle is.

**7. Record it** in `app-tooling.toml`:

```toml
[patterns.git-commit-stamp]
release = "vX.Y.Z"
```

or, when applied from a branch, `branch = "…"` and `commit = "…"` in place
of `release`.

## Verify

Run each and compare with the expected output. `plutil -extract` exits
non-zero when the key is missing, so a missing stamp cannot pass for an
empty one.

- **iOS, simulator build.** `make ios-build`, then:

  ```sh
  APP=$(xcodebuild -project <project> -scheme <scheme> \
    -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null |
    awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {d=$2} / FULL_PRODUCT_NAME/ {n=$2} END {print d"/"n}')
  plutil -extract AppGitCommit raw "$APP/Info.plist"
  plutil -extract CFBundleVersion raw "$APP/Info.plist"
  git rev-parse --short=12 HEAD; git rev-list --count HEAD; git status --porcelain
  ```

  `AppGitCommit` is the short SHA, with `-dirty` exactly when `git status
  --porcelain` printed anything; `CFBundleVersion` is the count, then `.1`
  if dirty or `.0` if not. The build log has a line
  `stamped AppGitCommit=…`.
- **iOS, signed.** After `make ios-device-build`,
  `codesign --verify --strict` on the product says `valid on disk`: the
  stamp went in before signing.
- **iOS, on the phone.** Only after the user has installed a stamped build:
  `make ios-device-which` names the commit. Before that it says the
  installed version is "not <count>.<dirty>", which is correct for a build
  from before the stamp.
- **Mac.** `make build`, then
  `plutil -extract AppGitCommit raw build/<App>.app/Contents/Info.plist`
  prints the SHA, and `codesign --verify` passes.
