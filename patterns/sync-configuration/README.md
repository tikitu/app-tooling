# sync-configuration

For an app that syncs through CloudKit: every build knows whether it may
sync and against which environment, and the app refuses to sync when the
answer is no or the sync state on disk belongs to another environment.
Builds that agents make cannot sync at all.

This is the safety net for the app's real data, so it is deliberately
small: two `Info.plist` keys set from the entitlements, two checks in the
app, one rule about which builds get the iCloud entitlement.

## The problems

- **`CKContainer(identifier:)` traps** for a container the app is not
  entitled to: a crash inside CloudKit, not an error. A sync engine made in
  such a build takes the process with it, and no `catch` helps.
- **A build signed ad hoc that claims the iCloud entitlements does not
  launch** (launchd refuses it, POSIX 163, with nothing in the app's log).
  So builds without a provisioning profile must not carry them; and a
  build without them must not make a `CKContainer` (above).
- **A simulator build traps too,** though its `Info.plist` is the device's:
  no profile grants a simulator the container. An app crashed on every
  launch in the simulator for days before anyone noticed.
- **A metadatabase carried between environments silently loses data.**
  SQLiteData keeps its sync state in a metadatabase named for the container,
  not the environment. A device that moves from Development to Production
  with its old state counts every table as already uploaded: Production
  gets only later edits, and nothing says so.
- **Any build an agent runs is a build that can sync,** unless something
  stops it. An agent's test run then edits the real data on every device.

## What it does

**Two entitlements files for the Mac app.** `<Target>.entitlements` has no
iCloud keys. `<Target>-iCloud.entitlements` is the same plus the iCloud
keys, with the environment pinned
(`com.apple.developer.icloud-container-environment`). `build.sh` signs with
the second only when it signs with a real identity and a provisioning
profile; an ad-hoc build (`make run-adhoc`, `make run-scratch`, every
agent's build) gets the first, so it can neither sync nor fail to launch.

**Two `Info.plist` keys, set from the entitlements.**
`scripts/stamp-sync-configuration.sh` writes `<App>SyncEnabled` (`true`
exactly when the iCloud entitlements are used) and `<App>CloudKitEnvironment`
(read out of that file) into the built `Info.plist`, before signing. Nothing
types them a second time. On iOS, where XcodeGen writes both the
entitlements and the `Info.plist` from `project.yml`, they sit side by side
there.

**Two checks in the app**, from app-utils' `CloudKitSyncConfiguration`
library (<https://github.com/tikitu/app-utils/blob/main/docs/CloudKitSyncConfiguration.md>):

- `SyncConfiguration.isEnabled`: the build declares sync and is not a
  simulator. Every CloudKit call is behind it, not only the sync engine.
- `CloudKitEnvironment.Check.prepare(databaseURL:sync:)`, before the
  database opens: a marker beside the metadatabase names its environment.
  A move from Development to Production deletes the metadatabase, so every
  row uploads; any other mismatch refuses sync. What an existing
  metadatabase without a marker belongs to is the app's history, and the
  app says (`unmarkedMetadatabase`).

**A check before TestFlight.** `make testflight-check-environment` refuses
unless the iOS spec says Production in both the entitlement and
`<App>CloudKitEnvironment`; `testflight-upload` depends on it. A
distribution-signed build is always Production
([`testflight`](https://github.com/tikitu/app-tooling/tree/main/patterns/testflight#icloud-and-cloudkit)
explains), so a declaration that says otherwise would check the sync state
against the wrong environment.

**No `eraseDatabaseOnSchemaChange`**, in any configuration. GRDB's
development convenience deletes the database when a migration changes,
and a debug build on a real database is a real database.

## What it asks of a project

- `scratch-data` (and `pattern-imports`): agents run the app with
  `make run-scratch`, on an ad-hoc build.
- A dependency on app-utils' `CloudKitSyncConfiguration` product (app-utils
  0.3.0 or later).
- A Mac app signed by `build.sh` (the starter's layout), and an iOS app in
  an XcodeGen `project.yml`. An Xcode project without XcodeGen can follow
  the same rules but needs its own wiring; `apply.md` says what to keep.
- Sync through SQLiteData's `SyncEngine`, for `CloudKitEnvironment.Check`;
  `SyncConfiguration` works with any CloudKit code.

## What it does not do

- **It does not plan a move to Production.** It makes the move safe on each
  device once the builds change; deploying the schema and moving every
  device together is the `testflight` pattern's README.
- **It does not move a device back to Development.** That is refused, and
  is its own plan.
- **It does not stop a person running a signed build on real data.** That
  is `make run`, and what it is for.
- **It does not check a signed bundle's actual entitlements.** The stamp
  is written from the file `build.sh` passes to `codesign`; reading the
  signature back afterwards is a later improvement.
