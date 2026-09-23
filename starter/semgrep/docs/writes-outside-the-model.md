# Database writes belong to the model

**Rule:** `database-write-outside-the-model`, in
`semgrep/writes-outside-the-model.yml`

## The rule

In the `UI` target, only `AppModel.swift` writes to the database. Every
control performs an `AppCommand`; the model does the writing.

## Why it fails silently

A "done" checkbox that updated the row itself would work perfectly when
clicked. What breaks is everything else: a script cannot mark an item done,
the menu bar's Mark Done (⌘↩) would be a second implementation that can drift
from the first, and a test of `perform(.setDone)` would pass while the
checkbox did something different. Nothing reports that; the checks simply stop
covering the thing people use. `docs/commands.md` has the invariant.

## What to do instead

Add a case to `AppCommand`, its decoding in `CommandFile.swift`, its row in
`docs/commands.md`, and perform it with `model.attempt(…)`.

## When a finding is not a bug

Form state is the one exception to "every control performs a command", and
it is already outside this rule: the remembered settings are user defaults
written through `@Shared`, not the database. If a view ever genuinely needs a
database write that is not a user action — there is none today — suppress
inline with `// nosemgrep: database-write-outside-the-model` and say why.

## What would break the rule

It recognises `.write { … }` and `.write(…)` on anything, in the `UI` target
only, except `.write(to: …)`, which is `Data` writing a file — the command
inbox's result, which the first version of the rule flagged. A write moved into a helper in another target and called from a view
slips past; so would a view in a new target.

## Validated against

A reconstruction: a view calling `database.write` itself is
flagged; `AppModel.swift`'s writes are not.
