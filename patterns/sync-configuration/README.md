# sync-configuration

For an app that syncs through CloudKit: every build knows whether it may
sync and against which environment, and the app refuses to sync when the
answer is no or the sync state on disk belongs to another environment.
Builds that agents make cannot sync at all.

This is the safety net for the app's real data, so it is deliberately
small: two `Info.plist` keys set from the entitlements, two checks in the
app, one rule about which builds get the iCloud entitlement, and a check
that each built app is signed as its `Info.plist` says.

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

**A check of every built app, from its signature.**
`scripts/check-sync-configuration.sh` reads what a bundle is actually
signed with, not the file the build was given, and compares it with its
`Info.plist`. Exactly two shapes pass, for the app and every extension in
it: **scratch** (`<App>SyncEnabled` false, no `<App>CloudKitEnvironment`,
no `com.apple.developer.icloud-*` entitlement anywhere) and **sync**
(`<App>SyncEnabled` true, and `<App>CloudKitEnvironment` the same as the
signed `icloud-container-environment`). `--expect scratch`, `sync` or
`production` (sync, on Production) fails the others: `build.sh` passes
the shape it just chose, and a TestFlight upload passes `production` on the
archive. A project whose scratch build is a separate app (its own bundle
id and App Group, as an Xcode project without `build.sh` needs) gives both
apps' ids and groups, and they are checked too.

It cannot be fooled by an empty answer. A bundle with no signature, or one
`codesign` cannot read, fails; it never reads as "no iCloud keys". A
simulator build's signature is ad hoc and has no entitlements, whatever the
build was given: the simulator's are linked into the executable's
`__TEXT,__entitlements` section, so for a simulator build that section is
read, from every architecture, and the copies must agree. Its tests
(`make sync-check-test`) sign fake bundles ad hoc, one per case.

**A check before TestFlight.** `make testflight-check-environment` refuses
unless the iOS spec says Production in both the entitlement and
`<App>CloudKitEnvironment`; `testflight-upload` depends on it. A
distribution-signed build is always Production
([`testflight`](https://github.com/tikitu/app-tooling/tree/main/patterns/testflight#icloud-and-cloudkit)
explains), so a declaration that says otherwise would check the sync state
against the wrong environment. With `testflight`'s `TESTFLIGHT_ARCHIVE_CHECK`,
the archive itself is checked as well, before anything is sent: the spec
check needs an XcodeGen spec, the archive check needs nothing but the
archive.

**No `eraseDatabaseOnSchemaChange`**, in any configuration. GRDB's
development convenience deletes the database when a migration changes,
and a debug build on a real database is a real database.

## What it asks of a project

- `scratch-data` (and `pattern-imports`): agents run the app with
  `make run-scratch`, on an ad-hoc build.
- A dependency on app-utils' `CloudKitSyncConfiguration` product (app-utils
  0.3.0 or later).
- A Mac app signed by `build.sh` (the starter's layout), and an iOS app in
  an XcodeGen `project.yml`. An Xcode project without either follows the
  same rules with its own wiring: two xcconfigs, a Run Script phase, and a
  scratch build that is a separate app; `apply.md` has the steps.
- Xcode's command-line tools (`codesign`, `lipo`, `segedit`; `clang` for
  the check's tests).
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
- **It does not check what is installed.** The check reads a built bundle
  or an archive; what a device or `/Applications` holds, and what a
  distribution export re-signs, it does not see.
