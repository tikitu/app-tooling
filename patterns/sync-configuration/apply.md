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

Then `uvx peru@1.3.5 sync`: `scripts/stamp-sync-configuration.sh` and
`mk/sync-configuration.mk`.

**2. Depend on the library.** In the `Package.swift` of the package whose
target makes the sync engine:

```swift
.package(url: "https://github.com/tikitu/app-utils", exact: "<version>"),
// …in that target's dependencies:
.product(name: "CloudKitSyncConfiguration", package: "app-utils"),
```

`<version>`: the first app-utils release with `CloudKitSyncConfiguration`,
or the one the package already pins if it is newer. Then
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
arguments. Remove the keys from `Resources/Info.plist` if it has them, with
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
- With `testflight`:

  ```make
  # A TestFlight upload must be Production (app-tooling: sync-configuration).
  SYNC_PREFIX := <App>
  include mk/sync-configuration.mk
  testflight-upload: testflight-check-environment
  ```

  With `SYNC_IOS_SPEC := …` before the include if the spec is not
  `apps/ios/project.yml`. Replace a hand-made
  `testflight-check-environment`.

**9. No `eraseDatabaseOnSchemaChange`.** Delete it wherever it is set,
`#if DEBUG` included, with a comment where it was if the database
configuration is otherwise silent on it.

**10. `AGENTS.md`**, beside what `scratch-data` added:

> Agents never run a build that can sync: `make run-scratch` builds ad hoc,
> without the iCloud entitlements. `make run` (signed, syncing) is for the
> user. Do not change `<Target>-iCloud.entitlements`, the
> `<App>CloudKitEnvironment` declaration or `unmarkedMetadatabase` without
> the user: they decide what happens to the synced data.

**11. Record it** in `app-tooling.toml`, with the decision and its reason:

```toml
[patterns.sync-configuration]
params = { prefix = "MyApp", unmarked_metadatabase = "development" }
# unmarked_metadatabase: no build synced against Production before the marker (user, YYYY-MM-DD).
```

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
- **TestFlight check.** With `testflight`: `make testflight-check-environment`
  prints `✓ … is Production` for a Production app and fails, exit 2, for a
  Development one. Change nothing to test the failure; run it with
  `SYNC_IOS_SPEC=/dev/null` instead, which must fail.
- `git grep -n eraseDatabaseOnSchemaChange` prints only comments.
