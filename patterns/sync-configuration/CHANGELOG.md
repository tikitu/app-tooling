# sync-configuration changelog

## Unreleased

- **`scripts/check-sync-configuration.sh` reads a built app's signature
  back** and fails unless it and the `Info.plist` agree: a scratch build
  with no iCloud entitlement anywhere, or a sync build whose signed
  environment is the one it declares. `--expect scratch|sync|production`
  fails the other shapes. Simulator builds are read from the executable's
  `__TEXT,__entitlements` section; an unreadable signature fails. Tests in
  `scripts/tests/check-sync-configuration-test.sh`, run by
  `make sync-check-test`; `mk/sync-configuration.mk` also gives
  `SYNC_CHECK` and `make sync-check`. To take it: include
  `mk/sync-configuration.mk` even without `testflight` (step 8), add
  `sync-check-test` to the project's tests, add the check after `build.sh`'s
  last `codesign` (step 6) and after the iOS build (step 9), and with
  `testflight` set `TESTFLIGHT_ARCHIVE_CHECK = $(SYNC_CHECK) --expect
  production`. A project with its own check script: `git rm` it and its
  tests before the update, and give what it checked as parameters
  (`SYNC_BUNDLE_ID`, `SYNC_APP_GROUPS`, `SYNC_SCRATCH_*`,
  `SYNC_APP_GROUP_KEY`).
- **`apply.md` says how to apply the pattern to an Xcode project without
  XcodeGen or `build.sh`**: a separate scratch app, two xcconfigs, and a
  Run Script phase that stamps the processed `Info.plist`. A project that
  followed its own wiring: compare it with "An Xcode project without
  XcodeGen or `build.sh`" and record any difference as a deviation.

## v0.2.0 (2026-10-20)

First version, from the conventions two apps grew by hand: two Mac
entitlements files (`<Target>-iCloud.entitlements` for builds that sync),
`scripts/stamp-sync-configuration.sh` to write `<App>SyncEnabled` and
`<App>CloudKitEnvironment` from them, `mk/sync-configuration.mk` with
`make testflight-check-environment`, and app-utils' `CloudKitSyncConfiguration`
library in place of each app's own `SyncConfiguration` and
`CloudKitEnvironment`. A project with hand-made versions: follow `apply.md`
from *Detect*, and ask the user what an unmarked metadatabase belongs to
before step 4.
