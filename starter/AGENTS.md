# Agent instructions

`README.md` has what the app is, the shape of the repo and the everyday
commands. `docs/` has the depth.

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
  means adding its command, its row in `docs/commands.md`, and its case in
  the decoder. Form state — typing in a field, a view toggle — is the one
  exception; what *commits* is the command, and `configure` is the scripted
  way to set remembered options.

* Read `docs/gotchas.md` before touching startup, the database bootstrap, or
  anything that looks needlessly odd. Every trap in it fails *silently*. When
  you find a new one, add it.

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

* **Platform code goes in its platform's package, never behind `#if os(…)`.**
  `Packages/StarterKit` is shared and must compile for iOS as well as the
  Mac (`make check` does both); Mac-only code goes in
  `Packages/StarterMacKit`. The reasons are in
  `rules/platform-conditionals.md`.

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
  `make check` after `make fmt`: see the `#if` trap in `docs/gotchas.md`.

* Run `make lint` (format check + ast-grep rules) before concluding work is
  finished. The rules catch mistakes that fail *silently*. **When one fires,
  read its `.md` in `rules/` before doing anything else**: it says whether to
  fix the code, allow an exception, improve the rule, or retire it, and how.
  Never suppress a rule without recording why in its document.

* **When a mistake recurs, or fails silently, make it a rule**: a check, the
  document that explains it (written first), and a test that shows it firing.
  `rules/README.md` has the convention.

<!-- practices -->
