# Changelog

What changed in each release of app-tooling. Each pattern has its own
`CHANGELOG.md` with what a project must do to catch up; this file is the
summary. How to make a release is in [`RELEASING.md`](RELEASING.md).

## Unreleased

- **New pattern `command-inbox`**, from the starter's command inbox and the
  apps that copied it: a script drives the running app through the same
  `perform` its controls use, and reads back what each command did. The
  runner and strict decoding are a Swift module imported into a package
  directory the project chooses; the inbox directory comes from `--commands
  <dir>`, outside any container (a sandboxed app opens it with one
  temporary exception), so a terminal never raises the "data from other
  apps" prompt. A project with a copy of the starter's inbox: follow
  `patterns/command-inbox/apply.md` and delete the copy.
- **`scratch-data`: `SCRATCH_ARGS`**, more launch arguments for `make
  run-scratch` (such as `--commands <dir>`). Nothing to do unless wanted
  (`patterns/scratch-data/CHANGELOG.md`).

## v0.5.1 (2026-10-22)

- **`build-warnings`: the App Intents skip can be set per target**, so a
  project with App Intents can still drop the `Metadata extraction
  skipped` warning from its extensions and test bundles; the check then
  fails `make` when a skipped target compiles App Intents code. Take the
  update; to use it, `apply.md` step 4 (`patterns/build-warnings/CHANGELOG.md`).
- **`build-warnings`: its App Intents check could stop `make` for a skip
  that was not there**, in a project that holds another importing the
  pattern, or whose `scripts/` is `Scripts/`, once it had App Intents
  code. Take the update; nothing else (`patterns/build-warnings/CHANGELOG.md`).
- **The starter takes `build-warnings`**, so its `make test` no longer
  prints the two `IssueReportingTestSupport` `ld` warnings. Without the App
  Intents skip: its one xcodebuild, of the shared package's library
  targets, does not print that warning. A project made from the starter
  adopts the pattern by its `apply.md`.

## v0.5.0 (2026-10-21)

- **New pattern `build-warnings`.** `mk/build-warnings.mk` exports
  `OMIT_DYNAMIC_TEST_SUPPORT=1`, removing swift-issue-reporting's
  `IssueReportingTestSupport` `ld` warnings (needs xctest-dynamic-overlay
  ≥ 1.11.0 or swift-issue-reporting 2.x), and stops every `make` run while
  `LM_SKIP_METADATA_EXTRACTION` and App Intents code are both in the
  project. A project with no App Intents may then set that skip, removing
  Xcode's "Metadata extraction skipped" warning. To adopt: follow
  `patterns/build-warnings/apply.md`.

## v0.4.0 (2026-10-20)

- **`testflight`: development installs can refuse real-data devices.**
  `mk/testflight.mk` has `testflight-device-guard`, which refuses a device
  in `TESTFLIGHT_ONLY_DEVICES`. Name the devices and add
  `$(TESTFLIGHT_DEVICE_GUARD)` to the install target's prerequisites,
  replacing any guard of the project's own
  (`patterns/testflight/CHANGELOG.md`).
- **The starter: a sandboxed `WKWebView`.** A new rule,
  `web-process-termination`, requires every `WKNavigationDelegate` to fail
  its waiting load when the page process dies, and `docs/gotchas.md` has
  three new traps: the `network.client` entitlement a sandboxed web view
  needs, that dying page process, and `Bundle.module`'s fallback to the
  build folder. Nothing to do; a project made from the starter that uses
  WebKit may copy the rule (`rules/`, `rule-tests/`) and the gotchas.

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
