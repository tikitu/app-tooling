# Changelog

What changed in each release of app-tooling. Each pattern has its own
`CHANGELOG.md` with what a project must do to catch up; this file is the
summary. How to make a release is in [`RELEASING.md`](RELEASING.md).

## Unreleased

- **`testflight`: development installs can refuse real-data devices.**
  `mk/testflight.mk` has `testflight-device-guard`, which refuses a device
  in `TESTFLIGHT_ONLY_DEVICES`. Name the devices and add
  `$(TESTFLIGHT_DEVICE_GUARD)` to the install target's prerequisites,
  replacing any guard of the project's own
  (`patterns/testflight/CHANGELOG.md`).

## v0.3.0 (2026-10-20)

- **`scratch-data`: `quit-running` could quit the real app**, matching a
  relative `$(APP)` that the real app's path also contains, then quitting
  by bundle id. It now quits only this checkout's build, by absolute path
  and pid. Update the pattern; delete any workaround (a target-specific
  absolute `APP` and empty `BUNDLE_ID`) and its recorded deviation
  (`patterns/scratch-data/CHANGELOG.md`). **The starter's own
  `quit-running`** had the same hazard and is fixed the same way; a project
  made from the starter replaces its copy.

- **`instruments-profiling`: `profile-mac.sh`** reports what xctrace
  launched and stops at once if it is a different copy of the app, kills
  only the process it launched (by pid), and no longer leaks its
  multi-gigabyte staging files after a recording that hung. Update the
  pattern, then delete the `instruments*.ktrace` files in `$TMPDIR` that
  earlier runs left and nothing holds open
  (`patterns/instruments-profiling/CHANGELOG.md`).

## v0.2.0 (2026-10-20)

- **The starter's `Makefile`** says where a release's `NOTES_FILE` goes:
  outside the worktree, not in `dist/`, which `make dist` deletes first.
  Nothing to do; a project made from the starter may copy the comment.
- **`scratch-data`**, a new pattern: `mk/scratch-data.mk` with
  `make run-scratch` (the Mac app in the background on scratch data,
  `--scratch-database`) and `make scratch-reset`, taken from the starter.
  `scratch-reset` now refuses a directory whose name lacks `scratch`. A
  project with its own copies of these targets replaces them
  (`patterns/scratch-data/CHANGELOG.md`). **At this release the starter
  takes it too**, in place of its own `run-scratch`, `scratch-reset` and
  `quit-running`; until then it keeps its own.
- **`sync-configuration`**, a new pattern for apps that sync through
  CloudKit: iCloud entitlements only in `<Target>-iCloud.entitlements`,
  used only by signed builds; `scripts/stamp-sync-configuration.sh` writes
  `<App>SyncEnabled` and `<App>CloudKitEnvironment` from them;
  `make testflight-check-environment`; and app-utils'
  `CloudKitSyncConfiguration` library (`SyncConfiguration`,
  `CloudKitEnvironment.Check`) in place of an app's own. Needs app-utils
  0.3.0 or later. A project with hand-made versions follows
  `apply.md`, and asks its owner what an unmarked metadatabase belongs to
  (`patterns/sync-configuration/CHANGELOG.md`).
- **Xcode 27, for every project, not only the starter.** A
  `Package.resolved` that pins `xctest-dynamic-overlay` fails to resolve,
  because Point-Free packages now depend on `swift-issue-reporting`. A
  project that gets it only through other packages runs
  `swift package resolve` in each package, which swaps that one pin and
  moves no other (not `swift package update`); one whose `Package.swift`
  names it changes the manifest as the starter did (v0.1.0, below). The
  steps are in `pattern-imports`' changelog, which every project's next
  update prints.
- **`pattern-imports`**: `make app-tooling-update` accepts an uncommitted
  change to `reup:` in `peru.yaml`, and nothing else, so a project moves to
  a new release by setting `reup:` and running the update, with no
  separate commit for the `reup:` edit. Nothing to do beyond taking the
  update.

## v0.1.0 (2026-10-05)

The first release.

- **Patterns** (`patterns/`): conventions packaged to be applied to
  existing projects and kept up to date there. Projects import them with
  peru, pinned at one commit of app-tooling (following a release tag or a
  branch), and record their own choices in `app-tooling.toml`.
- **`pattern-imports`**, the pattern every project takes first:
  `peru.yaml`, `mk/app-tooling.mk` (`make app-tooling-update`,
  `make app-tooling-check`), and the manual for all of the above.
- **Inbox** (`inbox/`): where improvements found in other projects wait to
  become patterns.
- **`git-commit-stamp`**, the first pattern: builds record their commit;
  `make ios-device-which` reads back which commit is on a phone.
- **`testflight`**: `make testflight-validate` and `make testflight-upload`
  send the iOS app to App Store Connect from a clean commit, with the
  commit count as the build number. Its README explains why distribution
  signing moves a CloudKit app to the Production environment.
- **`privileged-helper`**: a Mac app runs one command as root through a
  launchd daemon in its bundle (`SMAppService.daemon`), allowed once,
  instead of the password dialog every time. Documents only: the shape
  of the code, the traps, and what was found about trust.
- **`instruments-profiling`**: headless Instruments profiling of a Mac app.
  `make profile` records any template while a scenario runs, on a re-signed
  copy of the app and a copy of its data, refusing builds that can sync and
  checking which process it traced; `trace-query.py` reads traces as text
  (delays in Instruments' own categories, profiles, SwiftUI updates and
  their causes, memory); `profile-compare.sh` and `trace-compare.py` compare
  builds. A guide to the method, and a short skill.
- **The starter** takes `pattern-imports` and `git-commit-stamp` through
  peru, and stamps its Mac builds with their commit.
- **The starter's commands are `async`.** `AppModel.perform(_:)` and the
  command inbox can wait for a command (Touch ID, a dialog, a helper
  process) and report its outcome; the inbox file is taken before its
  commands run, so a second notification cannot run it twice. Controls
  still call `attempt(_:)` without awaiting: it starts the command with
  `Task.immediate`, so one that does not wait has finished when it returns.
  Nothing for an existing project to do; one that wants the same follows
  the starter's `AppModel`, `CommandInbox` and `docs/commands.md`.
- **The starter builds with Xcode 27.** Its packages depended on
  `xctest-dynamic-overlay`, which every Point-Free package has replaced with
  `swift-issue-reporting` 2.x, so the pinned `Package.resolved` no longer
  resolved. A project made from the starter changes the same in both
  `Package.swift` files (the URL to
  `https://github.com/pointfreeco/swift-issue-reporting`, `from: "2.1.0"`,
  and `package: "swift-issue-reporting"` on the `IssueReporting` product),
  then runs `make update-pins`.
