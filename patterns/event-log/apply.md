# Applying event-log

Read [`README.md`](README.md) first: it has the conventions and the reasons
for them. This file is how to bring a project's tables into line. The SQL
below uses the README's example names (`doses`, `medicines`); use the
project's.

The README has two owner decisions, timestamps and corrections. The steps
assume the recommended answers (`TEXT` timestamps, edit in place). Where a
step changes under another answer, it says so under **If the project
chose…**. Record which answer the project took (step 9).

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|event-log-docs`, and
  `app-tooling.toml` has `[patterns.event-log]`.
- **The event tables.** In the migrations (usually `Sources/Core/Schema.swift`,
  or wherever `registerMigration` is called):

  ```sh
  grep -rn --include='*.swift' -E 'registerMigration|CREATE TABLE|ALTER TABLE|CREATE (TEMPORARY )?TRIGGER' .
  grep -rn --include='*.swift' -E '"(occurred|happened|done|measured|recorded|logged|written|edited)At"|"zone"' .
  ```

  A table is an event table if each row says something happened at a time,
  and rows are added rather than one row kept up to date. List them, and
  for each, which of these it has:

  | Convention (README section) | What to look for |
  |---|---|
  | UUID `TEXT` primary key (1) | `"id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())` |
  | When it happened (1) | a `…At` column the person can set |
  | When it was written down (1) | a second `…At` column the app sets on insert and never changes |
  | Time zone (1) | a `zone` (or similar) `TEXT` column holding a `TimeZone` identifier |
  | Timestamp encoding (2) | `TEXT` columns with plain `Date` properties; or `REAL`/`INTEGER` columns, `Double` properties, `@Column(as: Date.…Representation.self)` |
  | Corrections (3) | `UPDATE` of the table in Swift; `DELETE`; a `retracts`/`isDeleted` column; triggers with `RAISE(ABORT` |
  | Definitions (4) | a table people edit, and whether it is versioned (`…Versions`, `editedAt`, `version`, `replaces`) |
  | Sync limits (5) | `UNIQUE`, `sequence`, compound `PRIMARY KEY (`, a table `REFERENCES` itself, reserved column names, `CHECK (… IN (…))` on an enum, permanent (not `TEMPORARY`) guard triggers, `eraseDatabaseOnSchemaChange`, `SyncEngine(for:` and its table list |

- **Something else doing this job.** A project that already made these
  decisions differently, and wrote down why (a `docs/data-model.md`, an
  ADR), is not brought into line silently: an `UPDATE`-free, append-only
  log with retractions, compensating operations on a ledger, `REAL`
  timestamps written by a non-SQLiteData writer, or a log on GRDB records
  rather than `@Table`. Describe what the project does and what this
  pattern would change to the user, and ask. Changing a correction model
  under real data is a migration of meaning, not of columns, and is never
  done as part of applying this pattern.
- **Not adopted:** tables with one timestamp, no zone, `UPDATE` in place,
  perhaps the starter's placeholder `items` table still there. The usual
  starting point.

## Parameters

| Parameter | Example | Where to find it |
|---|---|---|
| The event tables, and what each records | `doses`: a medicine taken | Detect, above; `docs/` for what they mean |
| For each, its "happened" column and its existing name | `takenAt` | the table; keep a name that is already in use and synced (a column cannot be renamed under sync) |
| Whether real data exists | yes: on the owner's phone | **ask the user.** An installed build that has run the migration, with entries in it, is real data, synced or not. A scratch database is not |
| Whether the app syncs, or will | `SyncEngine(for: database, tables: …)` in the code | the code; `app-tooling.toml` for `sync-configuration` |
| The correction model | edit in place | the owner's decision (README, 3); the project's own docs if it already decided |
| The timestamp encoding | `TEXT` | the owner's decision (README, 2); the existing columns |
| Where definitions live | in code (`Plan.swift`), or tables the person edits | the model code |
| The migrator | `myAppMigrator()` in `Sources/Core/Schema.swift` | `registerMigration` |

## Steps

The project must already have `pattern-imports`: a `peru.yaml` with the
`app-tooling` module.

**1. Import the documents.** This pattern has no `files/`, so there is one
rule. In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|event-log-docs: docs/app-tooling/event-log/
```

and beside the other rules:

```yaml
rule event-log-docs:
    pick: [patterns/event-log/README.md, patterns/event-log/apply.md, patterns/event-log/CHANGELOG.md]
    export: patterns/event-log
```

Then `uvx peru@1.3.5 sync`.

**2. Decide, per table, which path it takes**, and tell the user before
changing anything:

- **The schema has run nowhere with real data** (only scratch databases,
  previews, tests; or installed copies the user confirms are empty and
  have never synced): **change the migration that creates the table, in
  place.** It is not yet history. Say so in the commit and in a comment
  above the migration ("changed in place on <date>: no real data had been
  written"), because "never edit a migration that has run" is the rule
  everywhere else, and the next reader will wonder. Delete the scratch
  database afterwards (`make scratch-reset`, with `scratch-data`), or GRDB
  will not run the changed migration on it.
- **Real data exists: add a migration.** Never edit one that has run on
  it. Under sync, never drop or rename a column either: only add.

**3. A new event table.** In a new migration (or the one changed in place):

```swift
migrator.registerMigration("v3_doses") { db in
    try #sql(
        """
        CREATE TABLE "doses" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "medicineID" TEXT NOT NULL,
            "occurredAt" TEXT NOT NULL,
            "recordedAt" TEXT NOT NULL,
            "zone" TEXT NOT NULL,
            "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
        ) STRICT
        """
    ).execute(db)
    try #sql(#"CREATE INDEX "index_doses_on_occurredAt" ON "doses"("occurredAt")"#).execute(db)
}
```

`medicineID` is `REFERENCES "medicines"("id") ON DELETE CASCADE` only if
`medicines` is an identity table (step 6); a code-defined id is plain text.
Index what the screens filter or sort by; a plain index is fine under sync,
a `UNIQUE` one is not.

The Swift side, with the two values the app supplies set in one place, so
no caller can forget them:

```swift
@Table
public struct Dose: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// A medicine's id. Plain text: one this build does not know is shown
    /// as unknown, not refused.
    public var medicineID: String
    /// When it was taken. The person may correct it.
    public var occurredAt: Date
    /// When it was written down. Set on insert; never changed
    /// (docs/app-tooling/event-log/README.md, 1).
    public var recordedAt: Date
    /// The time zone it was recorded in, which decides its day for good.
    public var zone: String
    public var note: String = ""
}

extension Dose.Draft {
    /// A dose recorded now. `occurredAt` defaults to now; pass it to back-date.
    public init(medicine: String, occurredAt: Date? = nil, note: String = "", id: UUID? = nil) {
        @Dependency(\.date.now) var now
        @Dependency(\.timeZone) var timeZone
        self.init(
            id: id, medicineID: medicine, occurredAt: occurredAt ?? now, recordedAt: now,
            zone: timeZone.identifier, note: note)
    }
}

extension Dose {
    /// The calendar its day and time of day are read with: in its own zone,
    /// not the device's current one.
    public func calendar(from base: Calendar) -> Calendar {
        var calendar = base
        calendar.timeZone = TimeZone(identifier: zone) ?? base.timeZone
        return calendar
    }
}
```

Every place that groups events by day, or says "this morning", reads
through `calendar(from:)`. Find them: `grep -rn 'startOfDay\|isDateInToday\|dateComponents(' Sources`.

**If the project chose `REAL` timestamps:** the columns are `REAL NOT
NULL`, and the properties `Double` (seconds since 1970) with a computed
`Date` beside them, or a custom `QueryRepresentable` the project writes
once and uses on every timestamp. Not `Date.UnixTimeRepresentation`: it
stores whole seconds.

**4. An existing event table, real data, missing columns.** Add them as
nullable (an older build on another device writes rows without them), and
do not invent values for old rows: a guessed `recordedAt` or `zone`
presented as data is worse than an honest `NULL`.

```swift
migrator.registerMigration("v4_doses_recordedAt_zone") { db in
    // NULL on rows from before this migration: not recorded, not guessed.
    try #sql(#"ALTER TABLE "doses" ADD COLUMN "recordedAt" TEXT"#).execute(db)
    try #sql(#"ALTER TABLE "doses" ADD COLUMN "zone" TEXT"#).execute(db)
}
```

The Swift properties are `Date?` and `String?`; new rows always set them
(the `Draft` initialiser above), and a `nil` zone reads with the device's
calendar, which is what every row did before. Without sync, and with the
user's agreement, `NOT NULL` with a default is possible instead, but the
default is still a guess: say which in the migration's comment.

**5. Corrections**, as the project decided:

- **Edit in place** (recommended): the one write that moves a time changes
  `occurredAt` and nothing else; `recordedAt` is never in an `UPDATE`.
  Deleting is allowed for rows the person wrote; rows imported from
  elsewhere are refused in the write (`guard` and throw), not only hidden
  in the UI. Undo restores the deleted row with its `id`.
- **If the project chose append-only:** a `retracts TEXT` column (not a
  foreign key), `NULL` except on a retraction, with `CHECK`s that tie it to
  the row's kind; reads drop retracted rows and the retractions. Guard
  triggers as in README 5, made in `prepareDatabase` on *every*
  connection, the preview and test databases included:

  ```swift
  configuration.prepareDatabase { db in
      db.add(function: SyncEngine.$isSynchronizing)
      if try db.tableExists("doses") {
          try db.execute(sql: """
              CREATE TEMPORARY TRIGGER IF NOT EXISTS "doses_noUpdate"
              BEFORE UPDATE OF "medicineID", "occurredAt", "recordedAt", "zone", "note", "retracts"
              ON "doses" FOR EACH ROW
              WHEN NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()
              BEGIN SELECT RAISE(ABORT, 'the log is append-only: write a retraction'); END
              """)
          try db.execute(sql: """
              CREATE TEMPORARY TRIGGER IF NOT EXISTS "doses_noDelete"
              BEFORE DELETE ON "doses" FOR EACH ROW
              WHEN NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()
              BEGIN SELECT RAISE(ABORT, 'the log is append-only: write a retraction'); END
              """)
      }
  }
  ```

  The migration that creates the table makes the same triggers, since on a
  new database the table does not exist yet when `prepareDatabase` runs. A
  column added later joins the `UPDATE OF` list. An app that never syncs
  may use permanent triggers, as long as nothing will ever turn sync on.
- **If the project chose compensating operations:** that is a domain
  design, not a schema convention; write it down in the project's own docs
  with each operation's other side, and order operations with a hybrid
  logical clock (README 6).

**6. Definitions the person edits.** If they are a single table edited in
place, and real data exists, ask before splitting them: it is a data
migration (one identity row and one version row per existing row, the
version's `editedAt` the best date the project has). Otherwise create the
identity and versions tables as in README 4, point events at the identity,
and write the one query that picks the current version:

```swift
extension MedicineVersion {
    /// Each medicine's current version: the latest `editedAt`, then the
    /// highest `id`, so every device picks the same one.
    public static var current: Where<MedicineVersion> {
        Self.where { version in
            !MedicineVersion.as(LaterVersions.self)
                .where { later in
                    later.medicineID.eq(version.medicineID)
                        && (later.editedAt.gt(version.editedAt)
                            || (later.editedAt.eq(version.editedAt) && later.id.gt(version.id)))
                }
                .exists()
        }
    }
}

/// The same table again, under another name, for the subquery. Without
/// it, `version` in the inner `where` is the inner table, the condition is
/// never true, and every version counts as current.
private enum LaterVersions: AliasName {}
```

and an edit that appends a version only when something changed. Enum
columns: `TEXT`, no `CHECK … IN`, optional in Swift (or a `String` with a
computed known case). Add a test with two versions at the same
`editedAt`, and one older version: exactly one row comes back.

**7. Remove what sync forbids**, in a new migration if real data exists:
a `UNIQUE` column (rebuild the table without it: SQLite cannot drop a
column constraint), a self-referencing foreign key (same), a reserved
column name (only before sync: once synced it cannot be renamed, so ask).
Where the order a `sequence` gave matters, order by `occurredAt`, `id`
instead, or by a hybrid logical clock (README 6). Make sure every synced
table is in `SyncEngine(for:tables:)`.

**8. The project's documents.** In its data-model document (create
`docs/data-model.md` if there is none): the event tables, what each row
means, which column is "happened" and which "recorded", the zone rule, the
correction model with the reason, and anything this pattern says that the
project does differently. In `AGENTS.md`, one line:

```markdown
* **Event tables follow app-tooling's `event-log` pattern**
  (`docs/app-tooling/event-log/README.md`): two timestamps and a zone on
  every event, `recordedAt` never changed, enum values never `CHECK`ed,
  nothing sync forbids. Deviations are in `docs/data-model.md`.
```

**9. Record it** in `app-tooling.toml`:

```toml
[patterns.event-log]
params = { timestamps = "text", corrections = "edit-in-place" }
deviations = ["seasonEvents has no zone: the season is not a local-day thing"]
```

with a `deviations` line for each convention a table leaves out on purpose.

## Verify

Run each and compare with the expected output.

- **The schema, as the app makes it.** Run the app on scratch data (`make
  run-scratch`, with `scratch-data`), quit it, then, on the scratch
  database (the path the app logs as "database at …"):

  ```sh
  sqlite3 -readonly "$DB" '.schema doses'
  ```

  shows `occurredAt`, `recordedAt` and `zone`, and `STRICT`. An empty
  result means the wrong file or a table not created: check the path
  before concluding anything.
- **Nothing sync refuses.** On the same database:

  ```sh
  sqlite3 -readonly "$DB" "
    SELECT 'unique: ' || m.name || '.' || il.name
      FROM sqlite_schema m, pragma_index_list(m.name) il
      WHERE m.type = 'table' AND il.\"unique\" AND il.origin != 'pk'
        AND m.name NOT LIKE 'sqlite_%' AND m.name NOT LIKE 'grdb_%'
    UNION ALL
    SELECT 'self-reference: ' || m.name
      FROM sqlite_schema m, pragma_foreign_key_list(m.name) fk
      WHERE m.type = 'table' AND fk.\"table\" = m.name
    UNION ALL
    SELECT 'on delete: ' || m.name || '.' || fk.\"from\" || ' ' || fk.on_delete
      FROM sqlite_schema m, pragma_foreign_key_list(m.name) fk
      WHERE m.type = 'table' AND fk.on_delete IN ('RESTRICT', 'NO ACTION')
    UNION ALL
    SELECT 'reserved: ' || m.name || '.' || c.name
      FROM sqlite_schema m, pragma_table_info(m.name) c
      WHERE m.type = 'table' AND c.name IN ('creationDate', 'creatorUserRecordID', 'etag',
        'lastModifiedUserRecordID', 'modificationDate', 'modifiedByDevice',
        'recordChangeTag', 'recordID', 'recordType');
    SELECT 'tables checked: ' || count(*) FROM sqlite_schema
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%';"
  ```

  prints only the `tables checked:` line, its count the number of names
  `.tables` lists. Any other line is something `SyncEngine` will refuse,
  or a table it cannot sync. (Its own check runs when it is created; this
  one runs without CloudKit.)
- **Tests**, in the project's test target, against the in-memory database
  that runs the real migrator:
  - inserting through the `Draft` initialiser with `\.date.now` and
    `\.timeZone` overridden stores both, and `recordedAt` equals the
    overridden now;
  - moving an event's time changes `occurredAt` and leaves `recordedAt`;
  - an event recorded at 23:30 in `Asia/Tokyo` is on that Tokyo date when
    read with a calendar whose zone is `Europe/Amsterdam`;
  - a row with an enum value this build does not know decodes (as unknown),
    rather than failing the fetch;
  - with definitions: two versions at the same `editedAt` give the same
    current version whichever was inserted first;
  - with append-only: an `UPDATE` of a content column and a `DELETE` fail,
    and `UPDATE … SET "id" = "id"` (what SQLiteData runs before its first
    upload) succeeds. That the sync engine's own writes pass is seen only in
    a synced build: the flag it sets is not public.

  `\.timeZone` has no test value: a test that inserts through the `Draft`
  initialiser without overriding it fails with "has no test
  implementation", which is the point.

  `make test` passes, and its output names these tests: a filter that
  matches nothing also passes.
- **A synced build**, by the person: after the signed build first starts
  sync, the app's log shows no `SchemaError` ("Could not synchronize data
  with iCloud"), and a dose recorded on one device appears on the other
  with the same `recordedAt` and `zone`. Read the log with `/usr/bin/log`,
  not `log` (a zsh builtin that prints nothing).
