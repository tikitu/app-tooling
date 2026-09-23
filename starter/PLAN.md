# Starter — plan & documentation index

New here? Read this file, then `PROGRESS.md`. That is the whole onboarding.

---

## 0. Making it yours (delete this section once done)

This is a template. Copy it, then rename it in one pass:

```sh
git init
scripts/rename.sh MyApp                                   # display name "MyApp", bundle id com.example.myapp
scripts/rename.sh MyApp "My App" org.example.myapp        # or say both
make check && make test && make run
```

`rename.sh` rewrites the package, targets, `.app`, bundle id, display name,
scratch paths and every mention in the docs, renames files and directories to
match, and deletes itself. Then, by hand:

- `Resources/Info.plist`: `NSHumanReadableCopyright`, and
  `LSApplicationCategoryType` if utilities is wrong.
- `Makefile`: `TEAM_ID` and `DEVELOPER_NAME`, once you want `make dist`.
- `scripts/make-icon.swift`: the app's own mark.
- `README.md` and §1 below: what the app is for.
- `Item` in `Core/Schema.swift` is a placeholder, there so the commands, the
  keyboard and the tests have something to work on. Replace it — and its
  migration, and `plans/commands.md` — with the real model. Nothing has run
  that migration yet, so editing it is fine *until the first real launch*.
- `PROGRESS.md`: start the log.

## 1. What it is for

Describe the app: what it does, what it deliberately does not.

## 2. Shape of the repo

```
Packages/StarterKit/
  Core            the data: schema, migrations, bootstrap
  UI              AppModel, AppCommand, the command inbox, every view
  StarterMac      the app — a SwiftPM executable; its `Entry` prepares
                  dependencies before SwiftUI starts
Makefile build.sh             swift build + bundle + ad-hoc codesign
Resources/ StarterMac/        Info.plist; entitlements (sandboxed)
scripts/                      icon, send-commands, send-keys, window-id
semgrep/                      rules for invariants that fail silently
```

Dependencies are pinned: `Packages/StarterKit/Package.resolved` is committed
and every build uses it (`--force-resolved-versions`). `make outdated` says
what could move; `make update-pins` moves it, and the diff is the review.

## 3. Documentation index

- **`plans/commands.md`** — driving the app from a script: every command,
  the inbox transport, the scratch mode.
- **`plans/keyboard.md`** — the list's keyboard model: explicit selection on
  the model, → for actions, acting moves on, and verifying it without focus.
- **`plans/gotchas.md`** — traps. Every one fails silently. Read before
  "simplifying" anything odd.
- **`semgrep/README.md`** — the lint rules and their documents.
- **`PROGRESS.md`** — running log of what has been done, in order.
- **`CLAUDE.md`** — working agreements for agents. `AGENTS.md` points at it.

## 4. Everyday commands

```sh
make check           # compile (fast gate)
make test            # the test suite
make run             # build and launch, in front
make run-background  # build and launch behind whatever has focus
make run-scratch     # in the background, on scratch data, accepting commands
make screenshot      # build/window.png, by window id, without focus
make fmt             # reformat every Swift file in place
make lint            # format check + semgrep
make help            # everything else

scripts/send-commands.sh '<json>'   # drive a run-scratch app
```

Every `run` target quits a running copy first. `run` is for a person at the
keyboard; `run-background` and `run-scratch` are for agents, so that a check
never pulls the window in front of someone working.

## 5. Persistence

| What | Where | Why there |
|---|---|---|
| Items | SQLite, `Application Support/Starter/Starter.sqlite` in the container | a list that grows, queried and observed (`@FetchAll`) |
| Show Done | user defaults, via Sharing's `@Shared(.appStorage)` (`UI/Settings.swift`) | a single value |
| Selection | memory | a session's state |

Migrations are append-only and the database is never erased on schema change
(`semgrep/docs/erase-on-schema-change.md`).
