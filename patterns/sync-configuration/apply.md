# Applying sync-configuration

Read [`README.md`](README.md) first for what this does and why. **This
pattern guards the app's real data.** Change nothing that decides what
happens to stored data (the unmarked-metadatabase rule above all) without
the user's answer, and verify with builds and tests only: never launch a
build that can sync, on any device, as part of applying it.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|sync-configuration`.
- **Copied by hand, or grown in place** (the pattern came from such apps).
  Look for:
  - a Swift type `SyncConfiguration`, or an `Info.plist` key ending
    `SyncEnabled`, read before the sync engine starts;
  - a `CloudKitEnvironment` type, a key ending `CloudKitEnvironment`, or a
    `.environment` file beside the metadatabase;
  - two Mac entitlements files, one with iCloud keys (`-iCloud`, `-icloud`),
    and `build.sh` choosing between them on `SIGN_IDENTITY`;
  - a `testflight-check-environment` target;
  - a script that reads a built app's signature (`codesign -d
    --entitlements`, `segedit -extract __TEXT __entitlements`) and compares
    it with its `Info.plist`, often `scripts/check-sync-configuration.sh`
    with tests beside it: step 9 replaces it, and anything it checks that
    the pattern's does not is a parameter to add here first;
  - `eraseDatabaseOnSchemaChange` anywhere.

  For each, note what it does differently from this pattern: the key
  names, the entitlements file's name, what an unmarked metadatabase is
  taken to be. The steps replace them; differences in behaviour go to the
  user first.
- **Something else doing this job:** an `#if targetEnvironment(simulator)`
  or `#if DEBUG` around the sync engine, a separate scheme or bundle id
  that cannot sync, a check of the code signature. Describe it to the user
  and ask before changing anything.
- **Not adopted:** the app makes its sync engine unconditionally, and one
  entitlements file carries iCloud.

## Parameters

| Parameter | Where to find it |
|---|---|
| Key prefix (`<App>`) | what the app calls itself in `Info.plist` keys. A project that already has `<X>SyncEnabled` keeps `<X>`: renaming a key is a change with nothing to gain |
| Mac target name (`<Target>`) | the entitlements file's name in `build.sh` (`<Target>/<Target>.entitlements`) |
| Container identifier | `com.apple.developer.icloud-container-identifiers` in the entitlements; the `containerIdentifier:` the sync engine is made with |
| Environment | `com.apple.developer.icloud-container-environment` today, in the Mac entitlements and in `project.yml`. Not pinned: ask which the app's devices sync against |
| `unmarkedMetadatabase` | **ask the user.** Which environment every device's existing sync state was made against: `.development` if no build of the app has synced against Production yet, `.production` if all have. If devices differ, stop: that is a plan of its own |
| Logger subsystem | the app's existing `Logger(subsystem:)`, usually its bundle id |
| iOS spec | `project.yml`, usually `apps/ios/project.yml` |
| Separate scratch app, if any | an Xcode project without `build.sh` (below) has one: its bundle id and App Group, and the real app's, in its xcconfigs. With them, `SYNC_BUNDLE_ID`, `SYNC_APP_GROUPS`, `SYNC_SCRATCH_BUNDLE_ID`, `SYNC_SCRATCH_APP_GROUPS`, and `SYNC_APP_GROUP_KEY` if the `Info.plist` names the group. A project whose ad-hoc build is the same app leaves them unset |

## Steps

The project must already have `pattern-imports` and `scratch-data`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|sync-configuration: ./
    app-tooling|sync-configuration-docs: docs/app-tooling/sync-configuration/
```

and beside the other rules:

```yaml
rule sync-configuration:
    export: patterns/sync-configuration/files
rule sync-configuration-docs:
    pick: [patterns/sync-configuration/README.md, patterns/sync-configuration/apply.md, patterns/sync-configuration/CHANGELOG.md]
    export: patterns/sync-configuration
```

Then `uvx peru@1.3.5 sync`: `scripts/stamp-sync-configuration.sh`,
`scripts/check-sync-configuration.sh`, its tests in
`scripts/tests/check-sync-configuration-test.sh`, and
`mk/sync-configuration.mk`. A project with its own
`scripts/check-sync-configuration.sh` (Detect) deletes it, and its tests,
first: `git rm` them, then sync.

**2. Depend on the library.** In the `Package.swift` of the package whose
target makes the sync engine:

```swift
.package(url: "https://github.com/tikitu/app-utils", exact: "0.3.0"),
// …in that target's dependencies:
.product(name: "CloudKitSyncConfiguration", package: "app-utils"),
```

`0.3.0` is the first app-utils release with `CloudKitSyncConfiguration`;
keep the version the package already pins if it is newer. Then
`swift package resolve` and commit `Package.resolved`. A project with
both a Mac and an iOS package that pin the same packages keeps the two
`Package.resolved` files in step, as it already does.

**3. `SyncConfiguration`.** Where the app's other sync constants live:

```swift
import CloudKitSyncConfiguration

extension SyncConfiguration {
    /// Whether this build may touch CloudKit; see CloudKitSyncConfiguration.
    static let myApp = SyncConfiguration(infoPlistKey: "MyAppSyncEnabled")
}
```

and before **every** CloudKit call (the sync engine, `CKContainer` for
diagnostics, account-change handling):

```swift
guard SyncConfiguration.myApp.isEnabled else { return /* not syncing */ }
```

A hand-made `SyncConfiguration` goes, and its tests with it (the library
has them); call sites change from `SyncConfiguration.isEnabled` to
`SyncConfiguration.myApp.isEnabled`.

**4. `CloudKitEnvironment.Check`.** With the user's answer for
`unmarkedMetadatabase`:

```swift
extension CloudKitEnvironment.Check {
    static let myApp = CloudKitEnvironment.Check(
        infoPlistKey: "MyAppCloudKitEnvironment",
        containerIdentifier: MyAppSync.containerIdentifier,
        unmarkedMetadatabase: .development,  // the user's answer: <why>
        loggerSubsystem: "com.example.MyApp")
}
```

Where the database is opened, **before** it is opened, and only for the
real database (a `--scratch-database` run never syncs):

```swift
let refusal =
    isScratch ? nil
    : CloudKitEnvironment.Check.myApp.prepare(databaseURL: url, sync: .myApp)
```

Keep `refusal` where sync starts (a lock, or the app's model) and do not
start the sync engine when it is set; show it where the app shows that it
is not syncing. The database opens either way.

**5. The Mac entitlements.** Split them:

- `<Target>/<Target>.entitlements`: everything but the iCloud keys, with a
  comment saying where they went and why (an ad-hoc signature cannot
  carry them, and a build that claims them does not launch).
- `<Target>/<Target>-iCloud.entitlements`: the same, plus
  `com.apple.developer.icloud-container-identifiers`,
  `com.apple.developer.icloud-services`, push
  (`com.apple.developer.aps-environment` on macOS) and
  **`com.apple.developer.icloud-container-environment`, pinned**. A
  hand-signed build also needs `com.apple.application-identifier` and
  `com.apple.developer.team-identifier`, which Xcode would have added.

A project with `-icloud` renames the file to `-iCloud` (`git mv`), and
updates every reference (`git grep -n icloud.entitlements`).

**6. `build.sh`.** Choose the entitlements on the signing identity, refuse
a real identity without a profile, and stamp. Replace any existing
`SYNC_ENABLED`/environment logic with:

```bash
# A real signature gets the iCloud entitlements, and only with a profile that
# grants them; ad hoc gets none, so it can neither sync nor fail to launch
# (app-tooling: sync-configuration).
ENTITLEMENTS="<Target>/<Target>.entitlements"
ICLOUD_ENTITLEMENTS=""
if [ "$SIGN_IDENTITY" != "-" ]; then
	if [ -z "$PROVISION_PROFILE" ] || [ ! -f "$PROVISION_PROFILE" ]; then
		echo "✗ signing with '$SIGN_IDENTITY' needs a provisioning profile that grants iCloud;" >&2
		echo "  without one the app does not launch. 'make run-adhoc' builds one that does not sync." >&2
		exit 1
	fi
	ENTITLEMENTS="<Target>/<Target>-iCloud.entitlements"
	ICLOUD_ENTITLEMENTS="$ENTITLEMENTS"
fi
```

and after the bundle's `Info.plist` is written, before `codesign`:

```bash
# Whether this build may sync, and against which environment, from the
# entitlements chosen above (app-tooling: sync-configuration).
scripts/stamp-sync-configuration.sh "$APP/Contents/Info.plist" <App> $ICLOUD_ENTITLEMENTS
```

`$ICLOUD_ENTITLEMENTS` unquoted, so that an ad-hoc build passes two
arguments. After the last `codesign` of the app:

```bash
# The bundle must be signed as its Info.plist says, in the shape chosen
# above (app-tooling: sync-configuration).
scripts/check-sync-configuration.sh --prefix <App> --expect "$([ -n "$ICLOUD_ENTITLEMENTS" ] && echo sync || echo scratch)" "$APP"
```
 Remove the keys from `Resources/Info.plist` if it has them, with
any placeholders for them (`__SYNC_ENABLED__`).

**7. The iOS app**, in `project.yml`, on the app target. Beside the
entitlement:

```yaml
        # Must match <App>CloudKitEnvironment below (app-tooling: sync-configuration).
        com.apple.developer.icloud-container-environment: Production
```

and in its `info: properties:`:

```yaml
        # Set only alongside the iCloud entitlement: the app reads it before
        # touching CloudKit, which traps without the entitlement
        # (app-tooling: sync-configuration).
        <App>SyncEnabled: true
        # Must match icloud-container-environment above.
        <App>CloudKitEnvironment: Production
```

with the environment the app's devices actually use (Parameters). Then
`make ios-project`. The simulator never syncs, whatever these say.

**8. The Makefile.**

- Agents' builds are ad hoc: set `SCRATCH_BUILD` (`scratch-data`) to the
  target that builds with `SIGN_IDENTITY=-` (`build-adhoc`, or add one:
  the `build` recipe with `SIGN_IDENTITY="-"`), before its include.
- The check's parameters, and the fragment:

  ```make
  # Built apps are checked against their signature; a TestFlight upload
  # must be Production (app-tooling: sync-configuration).
  SYNC_PREFIX := <App>
  include mk/sync-configuration.mk
  ```

  With `SYNC_IOS_SPEC := …` before the include if the spec is not
  `apps/ios/project.yml`, and the separate scratch app's parameters, if
  any. Add `sync-check-test` to the target that runs the project's tests
  (`test: sync-check-test`, or the project's verify script runs
  `scripts/tests/check-sync-configuration-test.sh`).
- With `testflight`, after both includes:

  ```make
  testflight-upload: testflight-check-environment
  TESTFLIGHT_ARCHIVE_CHECK = $(SYNC_CHECK) --expect production
  ```

  `testflight-check-environment` only with an XcodeGen spec. Replace a
  hand-made `testflight-check-environment`, and a hand-made check of the
  archive in an upload script.

**9. Check every build.** `build.sh` checks the Mac app (step 6). Where the
Makefile builds the iOS app and knows its product, check it after the
build (the simulator's product passes as `sync`, from its linked
entitlements; the simulator never syncs whatever it says):

```make
ios-build: …
	…
	@$(SYNC_CHECK) "$(IOS_APP)"
```

A build target the project uses for agents, and that does not go through
`build.sh`, adds `--expect scratch`.

**10. No `eraseDatabaseOnSchemaChange`.** Delete it wherever it is set,
`#if DEBUG` included, with a comment where it was if the database
configuration is otherwise silent on it.

**11. `AGENTS.md`**, beside what `scratch-data` added:

> Agents never run a build that can sync: `make run-scratch` builds ad hoc,
> without the iCloud entitlements. `make run` (signed, syncing) is for the
> user. Do not change `<Target>-iCloud.entitlements`, the
> `<App>CloudKitEnvironment` declaration or `unmarkedMetadatabase` without
> the user: they decide what happens to the synced data.

**12. Record it** in `app-tooling.toml`, with the decision and its reason:

```toml
[patterns.sync-configuration]
params = { prefix = "MyApp", unmarked_metadatabase = "development" }
# unmarked_metadatabase: no build synced against Production before the marker (user, YYYY-MM-DD).
```

### An Xcode project without XcodeGen or `build.sh`

The rules are the same; the wiring is the Xcode project's own. Steps 5 to 7
and the `build.sh` parts of 8 and 9 become:

- **A separate scratch app.** Xcode's automatic signing has no ad-hoc path,
  and on the Mac an App Group needs a profile, so the build agents run is
  signed by Xcode too, and must be another app: its own bundle id (`.scratch`
  appended), its own App Group, and an App ID without the iCloud
  capability. The OS then lets it reach neither CloudKit nor the real
  app's data. Make it the configuration every default tool builds
  (`Debug`, which `xcodebuild`, ⌘R and the scheme's Run use), and add
  another (`Debug-iCloud`) for a debug build of the real app. Registering
  the new App ID and group in the developer account is the user's call:
  ask first.
- **Two xcconfigs**, one per kind of build, holding every value that
  differs between them, so that the difference is one reviewable file
  each, and set as each configuration's base configuration (the project's
  Info tab, Configurations):

  ```
  // Configurations/Scratch.xcconfig — the scratch app: no iCloud
  // (app-tooling: sync-configuration).
  MYAPP_BUNDLE_ID = com.example.MyApp.scratch
  MYAPP_APP_GROUP = group.com.example.myapp.scratch
  MYAPP_APP_ENTITLEMENTS = MyApp/MyApp.entitlements
  // Empty: the stamp writes MyAppSyncEnabled=false.
  MYAPP_ICLOUD_ENTITLEMENTS =
  ```

  ```
  // Configurations/iCloud.xcconfig — the real app, which syncs. Change
  // nothing here without the user (app-tooling: sync-configuration).
  MYAPP_BUNDLE_ID = com.example.MyApp
  MYAPP_APP_GROUP = group.com.example.myapp
  MYAPP_APP_ENTITLEMENTS = MyApp/MyApp-iCloud.entitlements
  MYAPP_ICLOUD_ENTITLEMENTS = $(MYAPP_APP_ENTITLEMENTS)
  ```

  The targets' own build settings then name the variables, in every
  configuration: `PRODUCT_BUNDLE_IDENTIFIER = $(MYAPP_BUNDLE_ID)` (an
  extension's `$(MYAPP_BUNDLE_ID).ShareExtension`) and
  `CODE_SIGN_ENTITLEMENTS = $(MYAPP_APP_ENTITLEMENTS)`; a value set on the
  target replaces the xcconfig's. An extension with an App Group needs an
  entitlements file per group, and its own variable. Code that opens the
  shared container needs the group too: put it in the `Info.plist`
  (`MyAppAppGroup = $(MYAPP_APP_GROUP)`, in the app's and each extension's)
  and pass that key as `SYNC_APP_GROUP_KEY`.
- **A Run Script phase** in the app target, last, named "Stamp Sync
  Configuration", with *Based on dependency analysis* off and
  `$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)` as its input file. Xcode signs
  after every phase, so the stamp is inside the signature:

  ```sh
  # Whether this build may sync, and against which CloudKit environment,
  # from the iCloud entitlements it signs with, if any; none means it may not
  # (app-tooling: sync-configuration). Xcode signs after every phase.
  "$PROJECT_DIR/../scripts/stamp-sync-configuration.sh" "$TARGET_BUILD_DIR/$INFOPLIST_PATH" MyApp ${MYAPP_ICLOUD_ENTITLEMENTS:+"$PROJECT_DIR/$MYAPP_ICLOUD_ENTITLEMENTS"}
  ```

  (`$PROJECT_DIR/..` when the `.xcodeproj` is one level below the
  repository root.) The target needs `ENABLE_USER_SCRIPT_SANDBOXING = NO`:
  the sandbox lets a phase write only its declared outputs, and the
  processed `Info.plist` belongs to another step. Remove the keys from the
  source `Info.plist`, as in step 6. One multiplatform target stamps the
  Mac and iOS apps alike.
- **The Makefile** sets the separate scratch app's parameters (Parameters),
  and checks each build of it: `$(SYNC_CHECK) --expect scratch` on the
  `Debug` products, Mac and simulator, and `--expect production` on the
  real app's archive, in the upload (`TESTFLIGHT_ARCHIVE_CHECK`, or the
  project's own upload script). There is no spec, so no
  `testflight-check-environment`. A verify script outside make runs the
  check through it: `make sync-check SYNC_CHECK_APPS=… SYNC_EXPECT=scratch`.
- **Record** the separate scratch app in `app-tooling.toml`, under
  `deviations`, with the reason (no `build.sh`).

## Verify

Builds and tests only; nothing here launches the app.

- `swift test` in the package (or `make test`) passes, and its count of
  tests dropped by exactly the hand-made `SyncConfiguration` and
  `CloudKitEnvironment` tests removed.
- **Ad hoc.** `make build-adhoc` (or the `SCRATCH_BUILD` target), then, on
  the bundle:

  ```sh
  plutil -extract <App>SyncEnabled raw build/<App>.app/Contents/Info.plist     # false
  plutil -extract <App>CloudKitEnvironment raw build/<App>.app/Contents/Info.plist  # exits 1: no such key
  codesign -d --entitlements - build/<App>.app 2>/dev/null | grep -c icloud   # 0
  ```

  The last prints `0` and exits 1; check that `codesign -d --entitlements -`
  on its own prints the base file's keys, so the `0` is not an empty
  command.
- **Signed**, only where the profile exists: `make build`, then the same
  two `plutil` commands print `true` and the pinned environment, and
  `codesign -d --entitlements -` shows the container and the same
  environment. Do not launch it.
- **iOS.** `make ios-build` passes; the built `Info.plist` has both keys
  (`plutil -extract` on the product in DerivedData).
- **The check.** `make sync-check-test` ends `N passed, 0 failed` and exits
  0. On a scratch build (`make build-adhoc`, or the `Debug` products),
  `make sync-check SYNC_CHECK_APPS=<app> SYNC_EXPECT=scratch` prints
  `✓ <app> is a scratch build`; the same with `SYNC_EXPECT=production`
  prints `✗ … expected a production build …` and exits non-zero. Both must
  print something: an empty result proves nothing. For a simulator build,
  `segedit <executable> -extract __TEXT __entitlements /dev/stdout` shows
  the entitlements the check read.
- **TestFlight check.** With `testflight`: `make testflight-check-environment`
  prints `✓ … is Production` for a Production app and fails, exit 2, for a
  Development one. Change nothing to test the failure; run it with
  `SYNC_IOS_SPEC=/dev/null` instead, which must fail.
- `git grep -n eraseDatabaseOnSchemaChange` prints only comments.
