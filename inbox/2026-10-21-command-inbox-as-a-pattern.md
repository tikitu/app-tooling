# The command inbox as a pattern, not only starter files

**Problem.** (inat_taxonomy_explorer, 2026-10-21; hub ticket 1PNS21Y.) An
existing app that wants the command inbox has nothing to import: it lives
only in the starter (`CommandInbox.swift`, `CommandFile.swift`,
`scripts/send-commands.sh`, `docs/commands.md`, the doc-examples test). So
each app copies and adapts it by hand, records that in `app-tooling.toml`
under a made-up table (`[from-starter.command-inbox]` there), and gets no
updates. ReadingRecord, TarPit and now inat_taxonomy_explorer each have a
copy.

**What worked** there (branch `command-inbox`, merged to its main):

- The inbox directory comes from a launch argument (`--commands <dir>`),
  beside the scratch data (`build/scratch/Commands`). For an unsandboxed app
  this avoids the container-access prompt entirely, with no entitlement
  exceptions (compare `2026-10-21-command-inbox-outside-container.md`). The
  app starts the inbox only when also given a database other than the real
  one.
- A command that needs loaded data waits for it (with a timeout), so a
  script can send commands straight after `make run-scratch`.
- `pause {seconds}` and `snapshot {}` (the app drawing its own windows,
  reporting the files) are inbox-only commands, handy for any app: animate,
  wait, photograph, in one request.
- A `state {}` command returning structured JSON (what the model built, and
  scroll offsets the views report back) lets a check read state, not pixels.
- `private(set)` on the model's state does the job of the
  `writes-outside-the-model` rule when the views' state is in memory, not the
  database: a view that changed it itself would not compile.
- Gotcha: `ScrollPosition.scrollTo(id:anchor:)` in a horizontal ScrollView
  nested in a vertical one also scrolls the outer one, and the outer
  `scrollTo(id:)` did not land on its target. Measuring each row's top
  (`onGeometryChange` in a named coordinate space) and `scrollTo(y:)` was
  reliable.

**Idea.** A `command-inbox` pattern: the decoding helpers (`AnyKey`, the
strict one-key-per-command check), the inbox runner, the script with
parameters for notification name, directory and process pattern, the
doc-examples test, and the docs. The app supplies its command enum and
`perform`.
