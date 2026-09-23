# Never erase the database on schema change

**Rule:** `erase-database-on-schema-change`, in
`semgrep/erase-on-schema-change.yml`

## The rule

`DatabaseMigrator.eraseDatabaseOnSchemaChange` is never set to `true` outside
tests — not even under `#if DEBUG`.

## Why it fails silently

It is SQLiteData's recommended setup, and it is recommended for a scratch
database: while iterating on a migration, GRDB notices that the migrations no
longer produce the schema on disk and deletes the file so they can run
fresh. Nothing is reported, because from the library's point of view nothing
went wrong.

Here, the database is the real data: the app is run day to day as a debug
build (`make run` builds `CONFIG=debug`), so `#if DEBUG` is not a guard. The
first time someone edits an applied migration, the next launch deletes
everything, and nothing says so.

## What it cost

Earlier apps kept this flag off from the start, for the same reason — one
database was "the only copy of months of collection" — and the
pfw-sqlite-data guidance, which puts it in every bootstrap, is exactly the
advice an agent will follow by default. That is
why it is a rule rather than a comment: the comment in `Schema.swift` is only
read by someone already editing that line.

## What to do instead

Never edit a migration that has run on a real device. Register a new one
that alters the schema, even during early development. If a schema really is
throwaway, delete the database file by hand, knowingly.

## When a finding is not a bug

- **In a test**, where every database is temporary. `Tests/` is excluded.
- **In a preview-only or sample database** that can never be pointed at the
  real file. Say so in a comment, and add the path to the rule's `exclude`
  rather than suppressing inline, so the exception is visible in one place.

## What would break the rule

It matches only a literal `= true` assignment to a property of that name.
Assigning a variable (`= isDebug`), or setting it through a helper, slips
past; so does the property being renamed in a future GRDB. Widen the pattern
if either happens rather than trusting silence.

## Validated against

No real history here yet, so against reconstructions of the two shapes the
library's documentation uses, both of which it flags:

- `migrator.eraseDatabaseOnSchemaChange = true` inside `#if DEBUG`.
- The same with no conditional.

And not flagged: the current `Schema.swift`, which only mentions the flag in
a comment, and `= false`.
