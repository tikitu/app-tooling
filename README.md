# app-tooling

The tools, patterns, skills and working agreements I use to build Mac (and
iOS) apps with agents, gathered in one place. It has two readers:

- **An agent in a new project**, pointed here to pick up the conventions and
  the tooling.
- **A human**, who wants to know what each part is, what it does for you,
  and above all *why* I prefer it.

Pieces that live elsewhere, and how to get them, are in
[external.md](external.md).

**To start a new Mac app**, copy [`starter/`](starter/) and run its setup
script: `cp -R starter ~/code/MyApp && cd ~/code/MyApp && git init &&
scripts/new-app.sh MyApp --with all`. The technical setup always comes;
how the project is *run* (tracking in markdown, commit and merge rules) is a
set of practices chosen with `--with`, described in
[`starter/practices/README.md`](starter/practices/README.md). An agent
setting up a project should ask the user which practices they want. The
starter's `README.md` has the rest of the first steps.

**Status: mostly an index.** Each item below is a sentence or two and a note
of where it was seen. The shape of this file is expected to change a lot as
we try small experiments and keep what works.

---

## Where these came from

| Repo | Role |
|---|---|
| `~/code/personal-time-tracking` | The earliest of the lineage. Two-package split, SwiftPM Mac build, Semgrep-with-docs, `SWIFTUI-RULES.md`. Its build system came from an outside template, credited in `starter/README.md`. |
| `~/code/when-did-you-last` | Copied from personal-time-tracking; added the command inbox, pinned dependencies, nonisolated default. |
| `~/code/author-alert` | Copied from when-did-you-last; added `swift-format` and "verify without taking focus". |
| `~/code/ReadingRecord` | An older app lifted into the lineage's shape afterwards (`plans/restructure.md` is the record of how). Origin of the Mac screen and keyboard-queue patterns. |
| `~/code/say-out-loud` | The newest, started from ReadingRecord's conventions. The cleanest current example of the whole set. |

`~/code/WhenDidYouLast` (capitalised, no hyphens) is a different, older,
abandoned repo. It is not a reference; don't confuse it with
`when-did-you-last`.

---

## 1. Working agreements (`AGENTS.md`)

The commit, merge and docs rules here are opt-in practices in the starter;
the verification rules are core.


- **One copy of the agreements, in `AGENTS.md`.** Claude Code reads
  `AGENTS.md` when there is no `CLAUDE.md` (since 2.1.277), so no pointer
  file is needed.
- **Commit straight to `main`; never merge a PR yourself.** Commit
  granularity replaces branches: a provisional change gets its own commit so
  it can be dropped. *Seen in:* all of the lineage.
- **Commit messages say why, in prose, and what was verified.** *Seen in:*
  all of the lineage.
- **Never commit code that doesn't compile.** Failing tests are sometimes
  acceptable; a broken build is not. *Seen in:* ReadingRecord, say-out-loud.
- **Verify by running, not by compiling.** Launch the app and look, or read
  back what it wrote, and say plainly what wasn't verified. *Seen in:* all
  of the lineage.
- **Verify without taking focus (or sound).** The laptop is in use while the
  agent works, so no activating windows, clicking or moving the pointer.
  *Seen in:* author-alert, ReadingRecord, say-out-loud.

## 2. Documentation shape

`PLAN.md`, `PROGRESS.md` and `PROBLEMS.md` are one opt-in practice in the
starter (`markdown-tracking`); `docs/` and the gotchas file are core.


- **`PLAN.md` as the index, depth in `plans/*.md`.** "Read PLAN.md and
  PROGRESS.md" should be the complete onboarding for a new session. *Seen
  in:* every repo in the lineage.
- **`PROGRESS.md`, a running log.** What was done, in order, and what was
  learned. *Seen in:* every repo in the lineage.
- **`PROBLEMS.md`: open questions and settled reasoning.** Keeps the "why we
  didn't do X" that commit messages lose. *Seen in:* every repo in the lineage.
- **`plans/gotchas.md`: failures that looked like something else.** Read it
  before "simplifying" anything that looks needlessly odd. *Seen in:* every
  repo in the lineage.
- **Docs change in the same commit as behaviour.** A stale doc is a bug,
  because the next session will trust it. *Seen in:* when-did-you-last
  onwards.
- **Markdown instead of an issue tracker.** Beads was tried and dropped;
  backlog lives in `plans/backlog.md`. *Seen in:* ReadingRecord (step 3 of
  its restructure), say-out-loud.

## 3. Build

- **Mac build with SwiftPM only, no Xcode project.** `Makefile` + `build.sh`
  run `swift build`, assemble the `.app`, and sign it ad hoc. *Seen in:* all
  of the lineage.
- **`make` as the single entry point.** `check`, `test`, `run`, `fmt`,
  `lint`, `help`, the same names in every repo. *Seen in:* all of the lineage.
- **iOS via XcodeGen, project git-ignored.** `apps/ios/project.yml` is the
  source; the `.xcodeproj` is generated and is a thin forwarding shell.
  *Seen in:* personal-time-tracking, ReadingRecord.
- **Platform split enforced by package manifests, not `#if`.** A
  cross-platform `…Kit` package and an iOS-only one, so a UIKit import in
  the wrong place is a build error. *Seen in:* personal-time-tracking,
  ReadingRecord.
- **Release pipeline in make.** `make dist` signs, notarizes, staples, zips
  and writes a checksum, with the version taken from a git tag. *Seen in:*
  all of the lineage.
- **App icon generated from a Swift script.** No binary assets to edit by
  hand. *Seen in:* all of the lineage.

## 4. Dependencies

- **Pinned, lockfiles committed.** `Package.resolved` is checked in and
  builds use it. *Seen in:* when-did-you-last onwards, and global `CLAUDE.md`.
- **`make check-pins`.** Checks that two packages resolving separately pin
  the same versions. *Seen in:* ReadingRecord (`scripts/check-pins.py`).
- **`make outdated` / `make update-pins`.** Report waiting updates; take them
  as a deliberate, reviewable diff. *Seen in:* say-out-loud, ReadingRecord.

## 5. App architecture

- **The Point-Free stack.** SQLiteData, StructuredQueries, Dependencies,
  Sharing, IssueReporting, CustomDump, Swift Testing; start from the
  `pfw-pfw` skill. *Seen in:* every repo in the lineage.
- **Every control performs an `AppCommand` via `AppModel.perform(_:)`.** A
  button that does its own work is a path no script can reach, and so never
  gets checked. *Seen in:* ReadingRecord, say-out-loud, when-did-you-last.
- **Nonisolated default actor isolation, everywhere.** Add `@MainActor`
  explicitly where needed. *Seen in:* when-did-you-last onwards.
- **Secondary screens declared once as data.** A window on the Mac, a sheet
  on iOS. *Seen in:* ReadingRecord `plans/screens.md`; global `CLAUDE.md`.
- **Keyboard-driven queues on the Mac.** Explicit selection, arrows, → for an
  actions menu, move on after acting. *Seen in:* ReadingRecord
  `plans/queues.md`, say-out-loud `plans/keyboard.md`; global `CLAUDE.md`.
- **Filenames with spaces.** `Edit a book.swift`. *Seen in:* ReadingRecord,
  say-out-loud.

## 6. Verifying without a human

- **Command inbox and scratch database.** `make run-scratch` launches the Mac
  app in the background on disposable data; `scripts/send-commands.sh` sends
  JSON commands and reads back a result. *Seen in:* when-did-you-last onwards.
- **`scripts/send-keys.swift`.** Posts key events to a process without
  activating it. *Seen in:* ReadingRecord, say-out-loud.
- **`scripts/window-id.swift` + `screencapture -l`.** Photographs one window
  by id without focus; `make screenshot` wraps it. *Seen in:* say-out-loud.
- **Snapshot tests, reviewed before committed.** In an interactive session
  the human sees before/after, never the half-finished states in between.
  *Seen in:* ReadingRecord.
- **`expectNoDifference` for values, `#expect` for the rest.** Failures print
  a diff instead of "Issue recorded". *Seen in:* all of the lineage.

## 7. Lint

- **`swift-format` with `respectsExistingLineBreaks: false`.** One canonical
  form, so diffs show changes rather than someone's wrapping. *Seen in:*
  author-alert, ReadingRecord, say-out-loud.
- **Semgrep rules, each paired with a document.** Only for invariants that
  fail silently; the doc says why, what it cost, and when a finding is not a
  bug. *Seen in:* all of the lineage (`semgrep/README.md`).
- **Candidate alternative: ast-grep rules with rationale.** The
  `rule-with-rationale` skill is the same idea with a different engine;
  untried in these repos.

## 8. Skills and rule books

- **`swiftui-pro`, `macos-design`.** Consulted before and after UI
  decisions. *Seen in:* every `CLAUDE.md` in the lineage.
- **`pfw-*` skills.** The Point-Free libraries' own guidance. *Seen in:*
  every `CLAUDE.md` in the lineage.
- **[`SWIFTUI-RULES.md`](SWIFTUI-RULES.md).** SwiftUI-on-the-Mac rules, each
  with the failure that taught it: transition crashes, layout, stale caches,
  rows, toolbars, Charts. Trimmed from the copy the lineage inherited. *Seen
  in:* personal-time-tracking, when-did-you-last, author-alert.
- **Project-local skill for iOS package testing.** An early experiment.
  *Seen in:* ReadingRecord `.claude/skills/`.

## 9. Gotchas that recur across repos

Candidates for a shared list, since several repos rediscovered the same ones:
`prepareDependencies` failing silently; zsh's `log` shadowing
`/usr/bin/log`; `devicectl` leaving 0-byte files; `open -n` leaving old copies
running; background-launched windows never running `.task`; `URL.path()`
keeping percent-encoding; Semgrep scanning only tracked files; `swift format`
breaking `#if` between modifiers.

---

## Open questions

- How does a new project consume this: copy files in, point `CLAUDE.md` here,
  install skills globally, or a mix?
- Which parts are Mac-only, and which apply to any Swift project?
