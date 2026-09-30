# testflight

The iOS app goes to your devices through TestFlight: `make testflight-upload`
archives a clean commit, checks it, and uploads it to App Store Connect;
the TestFlight app installs it.

## The problem

Installing from Xcode (or `xcrun devicectl`) needs the phone on the same
network as the Mac, a development-signed build that expires, and a person
at the Mac. TestFlight takes a build once, from one command, and every
device signed into the tester's account can install and update it, without
the Mac. It is also the path to the App Store, so an app that goes there
later has been through the same signing and checks all along.

## What it does

`scripts/testflight.sh` (through `make testflight-validate` and
`make testflight-upload`):

1. **Refuses** unless the tree is clean and `HEAD` is on the release branch
   (`main`, unless `TESTFLIGHT_BRANCH` says otherwise).
2. **Archives** the app, Release configuration, with automatic signing.
3. **Checks the archive** before anything leaves the machine:
   `CFBundleVersion` is `<count>.0` and `AppGitCommit` is `HEAD` (from
   `git-commit-stamp`), and `ITSAppUsesNonExemptEncryption` is set.
4. **Exports** with `destination: upload`: to App Store Connect's
   validation only, or to TestFlight. Xcode re-signs for distribution on
   the way, with a cloud-managed Apple Distribution certificate: no
   distribution certificate is needed on the Mac.

Everything it writes goes in `build/testflight/`: the archive, the export
options it generated, and a log of each step.

## Why this shape

- **The build number is the commit count** that `git-commit-stamp` writes,
  and Xcode is told not to replace it
  (`manageAppVersionAndBuildNumber: NO`). App Store Connect wants every
  upload's build number higher than the last; a commit count rises along
  one branch, which is why uploads come from one branch only. It also means
  every TestFlight build names its commit, and a phone reports it.
- **A dirty tree is refused, not stamped `.1` and uploaded.** A build on
  testers' phones that matches no commit is exactly what the stamp exists to
  prevent.
- **Export compliance is refused when undeclared.** Without
  `ITSAppUsesNonExemptEncryption`, every build waits in App Store Connect
  for someone to answer the question by hand. The answer is a legal
  declaration about the app, so the pattern cannot give it: the app's owner
  does, once, in `project.yml`.
- **Validate before the first upload.** `testflight-validate` runs App Store
  Connect's checks without creating a build, so a missing app record, a
  signing problem or a rejected `Info.plist` shows up without spending a
  build number.
- **Apple account or API key.** By default it authenticates as the Apple
  account signed into Xcode, which is what a person at their own Mac has.
  An App Store Connect API key (`ASC_KEY_PATH`, `ASC_KEY_ID`,
  `ASC_ISSUER_ID`) is for machines with no Xcode account; it stays out of
  the repository.

## iCloud and CloudKit

**Distribution signing moves an app to CloudKit's Production
environment.** Xcode's export rewrites
`com.apple.developer.icloud-container-environment` to `Production` (and
`aps-environment` to `production`), whatever the entitlements file says.
Production is a separate database from Development, empty until used, and
its schema has to be deployed from Development in the CloudKit Console
before records of a type can be saved there.

So for an app that syncs through CloudKit, moving to TestFlight is a move
of its data:

- Deploy the schema to Production (CloudKit Console) first.
- Every client of the same data moves together. A TestFlight phone and a
  development-signed Mac app are in different databases and never see each
  other.
- Installing a development build over a TestFlight one on the same device
  (or the reverse) switches that device's environment. Keep development
  installs to the simulator or a spare device once a device runs TestFlight
  builds.
- The local data on a device is kept across the install, but **the sync
  engine's saved state may not be.** SQLiteData, for one, keeps its state
  per container, not per environment, and uploads existing rows only for
  tables it has not synced before: a device that switches with its old
  state uploads only rows changed afterwards, and the new environment is
  silently partial. A device has to enter the new environment with fresh
  sync state, and the app has to do the reset (`devicectl` cannot delete
  files on a device). Check what the app's own sync engine does before
  planning the move.
- Xcode refuses to export for App Store Connect with Development
  (`iCloudContainerEnvironment`), but development profiles allow
  Production. The simplest end state is usually **every** build on
  Production, so a device never switches between the two.

`apply.md` stops at this for any app with iCloud entitlements, so that the
move is planned with the app's owner rather than discovered.

## What it asks of a project

- The `git-commit-stamp` pattern (and `pattern-imports`).
- An XcodeGen `project.yml`, as in the starter's
  [`docs/ios.md`](https://github.com/tikitu/app-tooling/blob/main/starter/docs/ios.md),
  and a make target that generates the Xcode project.
- A paid Apple Developer Program membership, and an app record in App
  Store Connect for the bundle id (a one-time step in the website).

It does not create the app record, manage testers, or submit to the App
Store.

## Files

Imported by peru, never edited in a project:

| File | Imported as |
|---|---|
| `files/scripts/testflight.sh` | `scripts/testflight.sh` |
| `files/mk/testflight.mk` | `mk/testflight.mk` |

`apply.md` has the steps; `CHANGELOG.md` what changed between releases.
