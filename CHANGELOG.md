# Changelog

What changed in each release of app-tooling. Each pattern has its own
`CHANGELOG.md` with what a project must do to catch up; this file is the
summary. How to make a release is in [`RELEASING.md`](RELEASING.md).

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
