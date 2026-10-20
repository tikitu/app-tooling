# sync-configuration changelog

## Unreleased

First version, from the conventions two apps grew by hand: two Mac
entitlements files (`<Target>-iCloud.entitlements` for builds that sync),
`scripts/stamp-sync-configuration.sh` to write `<App>SyncEnabled` and
`<App>CloudKitEnvironment` from them, `mk/sync-configuration.mk` with
`make testflight-check-environment`, and app-utils' `CloudKitSyncConfiguration`
library in place of each app's own `SyncConfiguration` and
`CloudKitEnvironment`. A project with hand-made versions: follow `apply.md`
from *Detect*, and ask the user what an unmarked metadatabase belongs to
before step 4.
