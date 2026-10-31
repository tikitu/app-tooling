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

> **Two points are open, for the owner to decide**: how timestamps are
> stored ([Timestamps](#2-timestamps-text-iso-8601-owner-decision)) and how
> mistakes are corrected
> ([Corrections](#3-corrections-edit-in-place-owner-decision)). Each has an
> options table. The rest of this pattern is written for the recommended
> answer; `apply.md` says what changes for the other ones.

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
  "medicineID" TEXT NOT NULL,          -- what it is about: a definition's id, see 4
  "occurredAt" TEXT NOT NULL,          -- when it happened; may be corrected
  "recordedAt" TEXT NOT NULL,          -- when it was written down; never changed
  "zone"       TEXT NOT NULL,          -- TimeZone.identifier where it was recorded
  "note"       TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
) STRICT
```

- **`id`: a UUID as `TEXT`, the only key.** `ON CONFLICT REPLACE DEFAULT
  (uuid())` lets a `Draft` insert without one; the app passes one when it
  needs to know it in advance (to undo, or to name it in a retraction).
  This is SQLiteData's own recommended shape for synced tables.
- **Two timestamps, `occurredAt` and `recordedAt`.** Every app studied
  keeps both, under various names (`happenedAt`, `doneAt`, `measuredAt`).
  These two names are the ones most of them use. `recordedAt` is set by the
  app, from `@Dependency(\.date.now)` so tests control it, when the row is
  inserted, and is never changed afterwards. Correcting when something
  happened changes `occurredAt` only, so the original moment survives as
  the gap between the two. An event recorded as it happens has the two
  equal, honestly.
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
- **A note**, `NOT NULL DEFAULT ''`, because people want to say why.
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

### 2. Timestamps: `TEXT` ISO-8601 (owner decision)

**Recommended: SQLiteData's default.** A Swift `Date` property with no
`@Column(as:)` is stored as `TEXT`, `2026-10-31 17:05:52.123`: UTC, no zone
designator, a space between date and time, milliseconds. (Swift
StructuredQueries 0.39.2, `Internal/Date+ISO8601.swift`; bound as text in
sqlite-data 1.12.0, `StructuredQueries+GRDB/QueryCursor.swift`.)

| Option | What it buys | What it costs | Which existing choices it matches |
|---|---|---|---|
| **`TEXT` ISO-8601, the default** (recommended) | No annotation on any `Date`; readable in `sqlite3` without conversion; sorts correctly as text; the column `DEFAULT CURRENT_TIMESTAMP` writes is the same format (without milliseconds) and decodes too | Milliseconds only: sub-millisecond differences round away. Arithmetic in SQL needs `julianday()` or `unixepoch()` first. Every write must go through a `Date` binding: a hand-written string in another format (`T`, `Z`) still sorts, but wrongly beside the others | The starter; four of the apps' event tables, and the edited-at columns of their definitions |
| **`REAL` seconds since 1970** | Sub-millisecond precision; `recordedAt - occurredAt` in plain SQL; what a writer outside SQLiteData (raw `sqlite3`, an extension) most naturally writes | Not a SQLiteData default: StructuredQueries' `Date.UnixTimeRepresentation` is **integer** seconds (`QueryRepresentable/Date+UnixTime.swift`), which would truncate the gap being measured, and `JulianDayRepresentation` is days, not seconds. So the app stores `Double` and converts, or writes its own representation; every `Date` property needs it, and forgetting one fails silently | One app, whose writer was raw `sqlite3` in an extension before SQLiteData was involved |

Neither is right for ordering writes across devices: where that matters
(below), a hybrid logical clock in an `INTEGER` column is a third,
separate thing, not a timestamp encoding.

Why the default: the events in these apps are recorded by a person, so
milliseconds are far finer than anything measured, and every place a
non-default representation is needed is a place to forget it. The app that
chose `REAL` did so because a non-SQLiteData writer came first; an app
in that position should keep what it has.

### 3. Corrections: edit in place (owner decision)

**Recommended: edit in place, keeping `recordedAt`.** Moving an event's
time changes `occurredAt`; fixing the note changes the note; an event
recorded by mistake is deleted. Undo puts it back with the same `id`.

| Option | What it buys | What it costs | Which existing choices it matches |
|---|---|---|---|
| **Edit in place, `recordedAt` kept** (recommended) | The least code: one row per event, read as it is. `recordedAt` still tells a corrected or back-dated event from one recorded at the time. Under sync, SQLiteData merges concurrent edits column by column, last edit wins, with nothing to write | No history of fixes. Two devices correcting the same field offline keep only the later edit, silently. A deleted row is gone everywhere | Three apps' event tables, and the one mutable column of a fourth's otherwise immutable log |
| **Append-only, with retraction rows** | Complete history: what the app believed at any moment can be replayed, which matters where the log is judged (a verdict, an audit). Nothing is ever lost to a race | Every read folds retractions in; a corrected time is a retraction plus a new row. The guard triggers must be `TEMPORARY`, made on every connection, let the sync engine through, and guard only content columns (see 5), or sync breaks. A retraction can arrive before what it retracts | One app (not synced), and one synced app's versions table |
| **Compensating operations** | Every change to a derived quantity has a stated other side, so two ways of computing a total cannot drift apart; nothing is edited | Domain-specific: needs a fold with invariants (balances, budgets) to make sense, and a total order of operations across devices (a hybrid logical clock) | One app, a budget, where a bare correction once made two figures disagree by its amount |

Why edit in place: for a personal log, the history of fixes is not
something anyone has asked to see, and the cost of the others is paid on
every read. Take append-only instead where the app has to be able to say
what it showed, or judged, at a time; compensating operations where events
feed totals that must reconcile.

**Deleting**, under edit in place: a row the person wrote may be deleted.
A row copied from somewhere whose truth lives elsewhere (an import from
Health, a calendar) is not deletable: deleting the copy leaves a gap the
next import fills straight back in. Refuse it in the write, not only in
the UI. Such rows have an id derived from the source (`HKSample.uuid`), so
re-importing an overlapping window costs nothing.

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
  StructuredQueries binds a `UUID` (`QueryBinding.swift`, line 75): an
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
1.12.0, `Documentation.docc/Articles/CloudKitSync.md` and
`CloudKit/SyncEngine.swift`. `SyncEngine` checks unique indexes,
foreign-key cycles and `ON DELETE` actions when it is created, and throws;
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
  conflicts"). This is what makes edit-in-place merge without code, and why
  a field that must not be lost to a race needs versions instead.
- **Triggers that refuse writes must let the sync engine through.** Make
  them `TEMPORARY`, in `prepareDatabase` on every connection, with `WHEN
  NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()`, and register
  that function there too (`db.add(function: SyncEngine.$isSynchronizing)`),
  since only a running `SyncEngine` registers it otherwise and the trigger
  fails with "no such function" in tests, previews and builds that do not
  sync. Guard `UPDATE OF` the content columns, not every update: SQLiteData
  runs `UPDATE … SET id = id`, outside sync, when it first uploads a
  table's rows. Received changes, leaving a share and signing out run with
  that function true and pass; a delete SQLiteData makes outside sync (its
  cleanup after a server reference violation) needs its own exception. The
  SQLiteData article's "Updating triggers to be
  compatible with synchronization" has the `WHEN` clause.
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
- It does not migrate an existing log from one correction model to
  another; `apply.md` says to ask before doing that.
