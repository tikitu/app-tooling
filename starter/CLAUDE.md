# Working agreements

## Documentation

* Keep `PLAN.md` as the index to the documentation for this codebase. Store
  in-depth documentation in `plans/whatever.md`.

* Record progress in `PROGRESS.md`. I should be able to tell a future agent
  "read PLAN.md and PROGRESS.md" and trust it is up to speed.

* Keep docs in step with behaviour, **in the same commit**. A doc describing a
  superseded design is a bug, because the next session will trust it.

* Plans, progress and backlog live in markdown in this repo, not in an issue
  tracker.

## Committing

* **Commit directly to `main`.** Branch only when asked, or when the work is
  genuinely speculative. Make commit granularity the lever instead: a
  provisional change goes in its own commit so it can be dropped cleanly.

* Commit messages say *why*, in prose, and what was verified.

* You may push PRs, but you MUST NOT ever merge them yourself to `main`.

* **Never commit code that does not compile.**

## Verifying

* **Verify by running, not by compiling.** Launch the app and look at it, or
  read back what it wrote. Say plainly which parts were not verified.

* **Verify without taking focus.** Someone may be using the machine while
  you work. Never activate a window, script a click or move the pointer.
  Use `make run-background` or `make run-scratch`, never plain `make run`,
  which brings the app to the front. `make screenshot` captures the window by
  id; `scripts/send-keys.swift <pid> down right return` posts keys to the
  process without activating it. If a check genuinely needs a click, say it
  is unverified rather than taking it.

* **Every control performs an `AppCommand` through `AppModel.perform(_:)`.** A
  control that does the work itself is a path no script can reach. Adding one
  means adding its command, its row in `plans/commands.md`, and its case in
  the decoder. Form state — typing in a field, a view toggle — is the one
  exception; what *commits* is the command, and `configure` is the scripted
  way to set remembered options.

* Read `plans/gotchas.md` before touching startup, the database bootstrap, or
  anything that looks needlessly odd. Every trap in it fails *silently*.

## Swift

* This project follows the Point-Free way. **Start with the `pfw-pfw` skill**
  if it is installed: it is the directory of the other `pfw-*` skills and
  says which apply. Load it before writing Swift. The libraries in use are
  SQLiteData, StructuredQueries, Sharing, Dependencies, IssueReporting,
  CustomDump and Swift Testing; without the skills, read their documentation
  in the SwiftPM checkouts under `.build/checkouts`.

  Assertions: use `expectNoDifference(actual, expected)` from CustomDump for
  equality on *values*, so a failure prints a diff. Keep plain `#expect` for
  counts, booleans, `nil` checks and `throws`.

* Default actor isolation is **nonisolated in every target**, UI included.
  Mark `@MainActor` explicitly where it is needed.

* **Filenames with spaces are this repo's style**: `Item list.swift`,
  `Main window.swift`. Preserve them.

* Before and after deciding on code, use the `swiftui-pro` skill. Use the
  `macos-design` skill to keep the UI reading as a modern Mac app. Keep things
  simple.

## Lint

* Formatting is the formatter's job. Run `make fmt` after writing Swift and do
  not hand-tune line breaks — `.swift-format` has
  `respectsExistingLineBreaks: false`, so there is one canonical form. Run
  `make check` after `make fmt`: see the `#if` trap in `plans/gotchas.md`.

* Run `make lint` (format check + Semgrep) before concluding work is finished.
  The Semgrep rules encode invariants that fail *silently*; each points at a
  document in `semgrep/docs/` saying why it exists and when a finding is not a
  bug. Semgrep scans only git-tracked files, so **`git add` first**.
