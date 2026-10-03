# Changelog

What changed in each release of app-tooling. Each pattern has its own
`CHANGELOG.md` with what a project must do to catch up; this file is the
summary. How to make a release is in [`RELEASING.md`](RELEASING.md).

## Unreleased

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
- **`privileged-helper`**: a Mac app runs one command as root through a
  launchd daemon in its bundle (`SMAppService.daemon`), allowed once,
  instead of the password dialog every time. Documents only: the shape
  of the code, the traps, and what was found about trust.
- **The starter** takes both patterns through peru, and stamps its Mac
  builds with their commit.
- **The starter's commands are `async`.** `AppModel.perform(_:)` and the
  command inbox can wait for a command (Touch ID, a dialog, a helper
  process) and report its outcome; the inbox file is taken before its
  commands run, so a second notification cannot run it twice. Controls
  still call `attempt(_:)` without awaiting: it starts the command with
  `Task.immediate`, so one that does not wait has finished when it returns.
  Nothing for an existing project to do; one that wants the same follows
  the starter's `AppModel`, `CommandInbox` and `docs/commands.md`.
