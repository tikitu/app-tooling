# event-log

For an app whose data is a record of what happened (a pill taken, a job
done, a measurement, an hour worked): rows are appended for things that
happened, and the present is derived from them. This pattern fixes the
details every such app otherwise decides again, and decides differently:
the event row's columns, how a timestamp is stored, how a mistake is
corrected, how an editable definition ("an activity", "a tag") keeps its
history, and what SQLiteData's CloudKit sync forbids in all of that.

Documents only. The bootstrap that opens and migrates the database is the
starter's, and is not repeated here.

> **Two points were the owner's to decide**, and were decided on
> 2026-10-31: timestamps are `TEXT` ISO-8601
> ([Timestamps](#2-timestamps-text-iso-8601-decided)), and corrections are
> append-only, with retraction rows
> ([Corrections](#3-corrections-append-only-with-retraction-rows-decided)).
> The options tables stay, so a project can see what it gives up by
> choosing otherwise; `apply.md` says what changes if it does.

## The problem

Six apps arrived independently at "append a row for each thing that
happened, derive the rest", and each re-decided the same details. What it
cost, or would have:

- **One timestamp, not two.** An app that stores only when something
  happened cannot tell a back-dated entry from one made at the time, and
  loses the correction when a time is moved: the original press is gone.
  Where data comes in late (an import, a sync, a person catching up), the
  gap between "happened" and "written down" is itself the measurement.
- **No time zone.** "Which day was this?" is computed from the device's
  calendar *now*. Travel, or a phone and a Mac in different zones, moves an
  evening dose to the next morning, after the fact, and a streak or a
  "done today" changes with it.
- **A schema that cannot sync.** A `UNIQUE` sequence number, a version
  number in a compound key, a self-referential foreign key, a column named
  `creationDate`, or append-only triggers that also refuse the sync
  engine's own writes: each is fine on one device and is refused, or
  breaks, when sync is turned on. By then real data is in it.
- **A newer build's value breaking an older one.** A `CHECK ("kind" IN
  (…))`, or decoding into a non-optional Swift enum, makes the older build
  on the other device refuse every row with a value it does not know.
- **Version numbers for edits.** Two devices editing the same definition
  offline both write "version 4", and nothing picks a winner.

## What it settles

### 1. The event row

```sql
CREATE TABLE "doses" (
  "id"         TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "medicineID" TEXT,                   -- what it is about (see 4); NULL on a retraction
  "occurredAt" TEXT,                   -- when it happened; NULL on a retraction
  "recordedAt" TEXT NOT NULL,          -- when this row was written down
  "zone"       TEXT NOT NULL,          -- TimeZone.identifier where it was recorded
  "retracts"   TEXT,                   -- on a retraction, the row it retracts (see 3)
  "note"       TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
  CHECK (("retracts" IS NULL) = ("medicineID" IS NOT NULL)),
  CHECK (("retracts" IS NULL) = ("occurredAt" IS NOT NULL))
) STRICT
```

- **`id`: a UUID as `TEXT`, the only key.** `ON CONFLICT REPLACE DEFAULT
  (uuid())` lets a `Draft` insert without one; the app passes one when it
  needs to know it in advance (to undo, or to name it in a retraction).
  This is SQLiteData's own recommended shape for synced tables.
- **Two timestamps, `occurredAt` and `recordedAt`.** Most of the apps
  studied keep both, under various names (`happenedAt`, `writtenAt`,
  `occurred_at`); one keeps only when it happened (`doneAt`,
  `measuredAt`). These two names are the ones most of them use. `recordedAt` is set by the
  app, from `@Dependency(\.date.now)` so tests control it, when the row is
  inserted. No row is ever changed (3), so a correction is a new row with
  its own `recordedAt`, and the original survives beside it. An event
  recorded as it happens has the two equal, honestly; a back-dated one
  shows the gap.
- **`zone`: the time zone the event was recorded in**, as
  `TimeZone.current.identifier` (`Europe/Amsterdam`, not an offset, so the
  zone's daylight-saving rules come with it). It decides for good which
  calendar day, and which part of the day, the event belongs to: read
  `occurredAt` with a calendar in that zone, never in the device's current
  one. Only one of the six apps stored it; the others recompute from the
  device calendar, which moves when travelling. When an event is
  back-dated, the zone is still the one it was recorded in: the app does
  not know where the person was, and the person nearly always was where
  they are.
- **A note**, `NOT NULL DEFAULT ''`, because people want to say why. It
  is the one column that may be edited in place (3).
- **Payload columns, typed and nullable**, for what the event carries (a
  dose, a quantity, a reading), rather than a JSON blob, unless the app is
  deliberately collecting raw data whose meaning is not decided yet (then a
  free-form `kind` and a flat text payload are the point, and say so).
- **Optional: precision.** Where a person says "this morning" rather than
  a time, store the start of the period in `occurredAt` and
  `"occurredIsExact" INTEGER NOT NULL DEFAULT 1` beside it, rather than
  inventing a time.

What it is *about* is a plain `TEXT` id. If the things are defined in code
(a fixed plan, a fixed list of treatments), the column holds that code's
stable string id and is not a foreign key; a row naming an id this build
does not know is shown as unknown, never refused. If they are defined by
the person, see 4.

### 2. Timestamps: `TEXT` ISO-8601 (decided)

**Decided by the owner on 2026-10-31: SQLiteData's default.** A Swift `Date` property with no
`@Column(as:)` is stored as `TEXT`, `2026-10-31 17:05:52.123`: UTC, no zone
designator, a space between date and time, milliseconds. (Swift
StructuredQueries 0.39.2, `Internal/Date+ISO8601.swift`; bound as text in
sqlite-data 1.12.1, `StructuredQueries+GRDB/QueryCursor.swift`.)

| Option | What it buys | What it costs | Which existing choices it matches |
|---|---|---|---|
| **`TEXT` ISO-8601, the default** (decided) | No annotation on any `Date`; readable in `sqlite3` without conversion; sorts correctly as text; the column `DEFAULT CURRENT_TIMESTAMP` writes is the same format (without milliseconds) and decodes too | Milliseconds only: sub-millisecond differences round away. Arithmetic in SQL needs `julianday()` or `unixepoch()` first. Every write must go through a `Date` binding: a hand-written string in another format (`T`, `Z`) still sorts, but wrongly beside the others | The starter; four of the apps' event tables, and the edited-at columns of their definitions |
| **`REAL` seconds since 1970** | Sub-millisecond precision; `recordedAt - occurredAt` in plain SQL; what a writer outside SQLiteData (raw `sqlite3`, an extension) most naturally writes | Not a SQLiteData default: StructuredQueries' `Date.UnixTimeRepresentation` is **integer** seconds (`QueryRepresentable/Date+UnixTime.swift`), which would truncate the gap being measured, and `JulianDayRepresentation` is days, not seconds. So the app stores `Double` and converts, or writes its own representation; every `Date` property needs it, and forgetting one fails silently | One app, whose writer was raw `sqlite3` in an extension before SQLiteData was involved |

Neither is right for ordering writes across devices: where that matters
(below), a hybrid logical clock in an `INTEGER` column is a third,
separate thing, not a timestamp encoding.

Why the default: the events in these apps are recorded by a person, so
milliseconds are far finer than anything measured, and every place a
non-default representation is needed is a place to forget it. The app that
chose `REAL` did so because a non-SQLiteData writer came first; an app
in that position should keep what it has.

### 3. Corrections: append-only, with retraction rows (decided)

**Decided by the owner on 2026-10-31: append-only, with retraction rows.**
A row is inserted and never updated or deleted. A mistake is corrected by
appending a **retraction**, a row whose `retracts` names the mistaken row;
the right event, if there is one, is then recorded afresh, back-dated if
need be. Moving an event's time is both, in one transaction: a retraction
of the old row and a new row with the new `occurredAt`. Undoing a
correction retracts the retraction (and the new row).

| Option | What it buys | What it costs | Which existing choices it matches |
|---|---|---|---|
| **Append-only, with retraction rows** (decided) | Complete history: what the app believed at any moment can be replayed, which matters where the log is judged (a verdict, an audit, a streak). Under sync the log is a set that only grows, so two devices converge by union and nothing is lost to a race | Every read folds retractions out; a corrected time is a retraction plus a new row. The guard triggers must be `TEMPORARY`, made on every connection, let the sync engine through, and guard only content columns (5), or sync breaks. A retraction can arrive before what it retracts | One app (not synced), and one synced app's versions table |
| **Edit in place, `recordedAt` kept** | The least code: one row per event, read as it is. `recordedAt` still tells a corrected or back-dated event from one recorded at the time. Under sync, SQLiteData merges concurrent edits column by column, last edit wins, with nothing to write | No history of fixes. Two devices correcting the same field offline keep only the later edit, silently. A deleted row is gone everywhere | Three apps' event tables, and the one mutable column of a fourth's otherwise immutable log |
| **Compensating operations** | Every change to a derived quantity has a stated other side, so two ways of computing a total cannot drift apart; nothing is edited | Domain-specific: needs a fold with invariants (balances, budgets) to make sense, and a total order of operations across devices (a hybrid logical clock) | One app, a budget, where a bare correction once made two figures disagree by its amount |

Why append-only: the history of what was recorded, and when it was
corrected, is the data these apps exist to keep, and the cost (a fold on
every read) is paid once, in one tested function.

**The fold.** A row is *in effect* unless a retraction that is itself in
effect names it. That is all: no ordering is needed, because a
retraction can only name a row that existed when it was written, so
chains of retractions never loop. Retractions are few, so read them all
(`id`, `retracts`), work out the set of retracted ids in Swift, and fetch
the events in effect with `"retracts" IS NULL AND "id" NOT IN (…)`.
Retractions may also live in a table of their own; that is how a table
that already holds real data, with `NOT NULL` content columns, becomes
append-only (`apply.md`, step 4). SQL
cannot do the fold itself: "not retracted by something not retracted" is
recursion through negation, which a recursive CTE does not allow.

**A retraction can arrive before its target**, under sync: `retracts` is
not a foreign key (5), so SQLiteData does not hold the retraction back.
The fold needs nothing special: the target is retracted from the moment
it arrives, and is never shown. A retraction whose target never arrives
retracts nothing; list it, if anywhere, only in a diagnostic view.

**The one mutable column is the note.** A column that never enters the
fold or anything derived from it may be edited in place; the guard
triggers leave it out, and SQLiteData's per-column last edit wins merges
concurrent edits. The note is that column by default. Name any other in
the project's docs, with the reason, and freeze it before it ever starts
to matter to a result.

**Imported rows** (copies of something whose truth lives elsewhere: Health
samples, a calendar) take an id derived from the source (`HKSample.uuid`)
and are inserted only when that id is not already there, never replaced,
so re-importing an overlapping window costs nothing. A retraction of an
imported row then stays in effect when the import runs again.

**When edit in place is acceptable instead**: an app that already syncs
and whose history has been edited in place. Its past corrections left no
trace, so retractions from now on would make only part of the history
complete, and changing the model is a migration of meaning, not of
columns. Such an app keeps edit in place, keeps `recordedAt` out of every
`UPDATE`, deletes only rows the person wrote (an imported row's copy would
come straight back), and records the choice as a deviation.

### 4. Editable definitions: identity plus versions

Things the person defines and later edits (activities, medicines, tags) are
two tables: the identity, which events point at and which is never edited,
and its versions, appended one per edit.

```sql
CREATE TABLE "medicines" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
) STRICT;

CREATE TABLE "medicineVersions" (
  "id"         TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "medicineID" TEXT NOT NULL REFERENCES "medicines"("id") ON DELETE CASCADE,
  "editedAt"   TEXT NOT NULL,
  "name"       TEXT NOT NULL DEFAULT '',
  "form"       TEXT,                     -- an enum's raw value, deliberately unchecked
  "isDeleted"  INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX "index_medicineVersions_on_medicineID" ON "medicineVersions"("medicineID");
```

- **Why two tables**: "many rows per thing, keyed by its id and a version
  number" needs a compound key or a unique index, and sync allows neither
  (5); an event would also have nothing unique to point at.
- **The current version is the latest `editedAt`**, ties broken by the
  version's `id`, so every device picks the same row. Not a version number:
  two devices editing offline both write the same number. Clock skew
  between one person's devices is negligible at this scale.
- **Deleting is a version** with `isDeleted = 1`. The events are kept;
  undeleting is another version. An edit that changes nothing appends
  nothing.
- **When several people edit the same thing** and a lost edit matters,
  "latest wins" hides the conflict. Then each version names the versions it
  replaces (a `replaces` column holding their ids), the current versions
  are those nothing replaces, and more than one is a conflict to show.
  `replaces` is not a foreign key (5), and holds ids in lower case, the way
  SQLiteData binds a `UUID` (`QueryCursor.swift`, `withLowercasedUTF8Text`): an
  upper-case `uuidString` from `JSONEncoder` never matches.
- **`CHECK` constraints for "at most one of"**, and for column groups that
  are all set or all `NULL` (a cadence stored as six columns): rules two
  optionals cannot express, enforced where nothing can get round them.
- **Enum values are deliberately *not* checked.** No `CHECK ("form" IN
  (…))`, and in Swift either an optional raw-representable enum (an unknown
  value reads as `nil`) or a `String` with a computed `knownForm`. A newer
  build's case then reaches an older build as "unknown", not as a refused
  row. A new meaning gets new columns rather than reusing old ones, so that
  an older build does not misread it.

### 5. What SQLiteData's CloudKit sync forbids

Design within these from the first migration, even before sync is on: the
schema is very hard to change once real data is in it. From sqlite-data
1.12.1, `Documentation.docc/Articles/CloudKitSync.md` and
`CloudKit/SyncEngine.swift`. `SyncEngine` checks unique indexes,
foreign-key cycles and (on a table with exactly one foreign key) `ON
DELETE` actions when it is created, and throws;
a table without a primary key is not a `PrimaryKeyedTable`, which
`SyncEngine(for:tables:)` requires.

- **One single-column primary key per table**, a UUID as text. Join tables
  too ("Primary keys on every table").
- **No unique index besides the primary key** (`SyncEngine.swift`,
  `validateSchema`, "Uniqueness constraints are not supported"). So no
  `UNIQUE` sequence number: order by `occurredAt`, then `id`.
- **No cycles among foreign keys, including a table referencing itself**
  ("Cycles are not currently permitted in schemas", `tablesByOrder`). A
  `replaces` or `retracts` column is plain text, not `REFERENCES`.
- **`ON DELETE` is `CASCADE`, `SET NULL` or `SET DEFAULT`**, never
  `RESTRICT` or `NO ACTION`; and every table a foreign key points at is
  synchronized too.
- **No reserved CloudKit names as columns**: `creationDate`,
  `creatorUserRecordID`, `etag`, `lastModifiedUserRecordID`,
  `modificationDate`, `modifiedByDevice`, `recordChangeTag`, `recordID`,
  `recordType` ("Avoid reserved CloudKit keywords", which says the list is
  not exhaustive). `createdAt` and `recordedAt` are fine.
- **Never remove or rename a column, or rename a table**, once a build has
  synced ("Disallowed migrations"). **A column added later is nullable, or
  has a default with `ON CONFLICT REPLACE`** ("Adding columns"): an older
  build writes rows without it.
- **Conflicts are resolved per column, last edit wins** ("Record
  conflicts"). This is what merges concurrent edits of a note without
  code, and why anything that must not be lost to a race is appended, not
  edited.
- **Triggers that refuse writes must let the sync engine through.** Make
  them `TEMPORARY`, in `prepareDatabase` on every connection, with `WHEN
  NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()`, and register
  that function there too (`db.add(function: SyncEngine.$isSynchronizing)`),
  since only a running `SyncEngine` registers it otherwise and the trigger
  fails with "no such function" in tests, previews and builds that do not
  sync. Guard `UPDATE OF` the content columns, not every update: SQLiteData
  runs `UPDATE … SET id = id`, outside sync, when it first uploads a
  table's rows; and leaving the mutable note out of the list is what lets
  it be edited. Received changes, leaving a share and signing out run with
  that function true and pass. One delete SQLiteData makes with it false:
  when the server refuses a row because its parent is gone, SQLiteData
  deletes the local row, for a table with exactly one foreign key
  (`SyncEngine.swift`, `.referenceViolation`). So on such a table the
  delete guard refuses only while the parent exists, or the row has none
  (a retraction): `AND (OLD."medicineID" IS NULL OR EXISTS (SELECT 1 FROM
  "medicines" WHERE "id" = OLD."medicineID"))`. The SQLiteData
  article's "Updating triggers to be compatible with synchronization" has
  the `WHEN` clause.
- **`eraseDatabaseOnSchemaChange` stays off**, in every configuration
  (the starter's `rules/erase-on-schema-change.md` enforces it, and
  `sync-configuration` says why).
- **Every table is listed in `SyncEngine(for:tables:)`.** A table missing
  from the list is simply not synced; nothing complains.
- **Ids in text you write yourself are lower case.** StructuredQueries
  binds a `UUID` as lower-case text; `uuidString` is upper case, and a row
  written with it is never found by `id`.

### 6. Ordering across devices, when it matters

Order events by `occurredAt`, then `id`. That is enough for a log people
read. Where the *order of writing* has meaning across devices (a fold whose
result depends on what each writer had seen, a version that must sort
after the one it replaces), add a hybrid logical clock: an `INTEGER` column
computed by the app as `max(now, highest seen + 1)`, in microseconds,
ordered with the `id` as tie-break. It is a sort key, not a timestamp to
show.

### 7. The database itself

Opening, migrating, the in-memory database for previews and tests, scratch
data: the starter's
[`Schema.swift`](https://github.com/tikitu/app-tooling/tree/main/starter/Packages)
(in `Sources/Core/`) already does it, and
[`scratch-data`](https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-data)
covers the scratch copy. Add the event tables as migrations there.

## What it asks of a project

SQLiteData, with tables declared in SQL migrations (`#sql`), as the starter
has. Nothing to install. A project that syncs should have
[`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration);
this pattern does not require it.

## What it does not do

- It carries no code. The tables are the app's, and so are their queries.
- It does not decide what a "day" is (midnight, or 04:00 for a night owl),
  only which time zone it is computed in.
- It does not cover sharing records with other iCloud users beyond the
  `replaces` note in 4; sharing has more rules (which foreign keys a shared
  record may have) that belong in a pattern of their own.
- It does not rewrite history. A table with real data becomes
  append-only from the migration that adds retractions on; the corrections
  made in place before then left no trace, and stay that way.
