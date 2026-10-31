# Applying event-log

Read [`README.md`](README.md) first: it has the conventions and the reasons
for them. This file is how to bring a project's tables into line. The SQL
below uses the README's example names (`doses`, `medicines`); use the
project's.

The README's two owner decisions are taken (2026-10-31): `TEXT`
timestamps, and append-only corrections with retraction rows. The steps
assume both. Where a project has reason to differ (README 3 says when),
the step says what changes under **If the project…**. Record any
difference as a deviation (step 9).

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
- **Not adopted:** tables with one timestamp, no zone, `UPDATE` and
  `DELETE` in place, perhaps the starter's placeholder `items` table still
  there. The usual starting point.

## Parameters

| Parameter | Example | Where to find it |
|---|---|---|
| The event tables, and what each records | `doses`: a medicine taken | Detect, above; `docs/` for what they mean |
| For each, its "happened" column and its existing name | `takenAt` | the table; keep a name that is already in use and synced (a column cannot be renamed under sync) |
| Whether real data exists | yes: on the owner's phone | **ask the user.** An installed build that has run the migration, with entries in it, is real data, synced or not. A scratch database is not |
| Whether the app syncs, or will | `SyncEngine(for: database, tables: …)` in the code | the code; `app-tooling.toml` for `sync-configuration` |
| The correction model | append-only, with retraction rows | decided (README, 3); edit in place only for a synced app whose history was already edited that way |
| The mutable columns | `note` | the README's default; any other the project names, with the reason |
| The timestamp encoding | `TEXT` | decided (README, 2); keep `REAL` columns a non-SQLiteData writer already fills |
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

- **The migration that creates the table has run nowhere that matters**
  (only scratch databases, previews and tests; no installed copy has run
  it, or the user agrees to delete the database of every copy that has,
  and nothing has synced): **change that migration in place**, to the
  shape in step 3. It is not yet history. Editing it changes nothing on a
  database that already ran it: GRDB records a migration by name and does
  not run it again, so such a copy keeps the old table. Hence "nowhere
  that matters", and deleting the scratch database afterwards (`make
  scratch-reset`, with `scratch-data`). Say so in the commit and in a
  comment above the migration ("changed in place on <date>: it had run on
  no real data"), because "never edit a migration that has run" is the
  rule everywhere else, and the next reader will wonder.
- **Real data exists: add a migration** (step 4). Never edit one that has
  run on it. Under sync, never drop or rename a column either: only add.
- **Real data exists, the app syncs, and its history has been edited in
  place**: keep edit in place (README 3, "When edit in place is acceptable
  instead"), add the missing columns as in step 4, and record the
  deviation (step 9). Ask the user first.

**3. The event table**, new, or a migration changed in place. A typical
starting point is one timestamp, edited in place:

```sql
CREATE TABLE "doses" (
    "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
    "medicineID" TEXT NOT NULL,
    "takenAt" TEXT NOT NULL,
    "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
) STRICT
```

and becomes, in the same migration:

```swift
migrator.registerMigration("v2_doses") { db in
    // Changed in place on 2026-11-02: it had run on no real data. Append-only
    // (docs/app-tooling/event-log/README.md, 3).
    try #sql(
        """
        CREATE TABLE "doses" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "medicineID" TEXT,
            "occurredAt" TEXT,
            "recordedAt" TEXT NOT NULL,
            "zone" TEXT NOT NULL,
            "retracts" TEXT,
            "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
            CHECK (("retracts" IS NULL) = ("medicineID" IS NOT NULL)),
            CHECK (("retracts" IS NULL) = ("occurredAt" IS NOT NULL))
        ) STRICT
        """
    ).execute(db)
    try #sql(#"CREATE INDEX "index_doses_on_occurredAt" ON "doses"("occurredAt")"#).execute(db)
    try #sql(#"CREATE INDEX "index_doses_on_retracts" ON "doses"("retracts")"#).execute(db)
    try installDoseGuards(db)
}
```

- The "happened" column takes the name `occurredAt` while that is still
  free to change; with real data, keep the old name.
- Every content column is nullable, and a `CHECK` ties each one that a
  real event must have to `"retracts" IS NULL`. Payload columns that are
  optional anyway (a quantity) need no `CHECK`.
- `medicineID` is `REFERENCES "medicines"("id") ON DELETE CASCADE` only
  if `medicines` is an identity table (step 6); a code-defined id is plain
  text. `retracts` is never a foreign key.
- Index what the screens filter or sort by; a plain index is fine under
  sync, a `UNIQUE` one is not.

The Swift side. The values the app supplies are set in one place, so no
caller can forget them, and every write is an insert:

```swift
@Table
public struct Dose: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// What was taken; `nil` on a retraction. Plain text: an id this build
    /// does not know is shown as unknown, not refused.
    public var medicineID: String?
    /// When it was taken; `nil` on a retraction.
    public var occurredAt: Date?
    /// When this row was written down (docs/app-tooling/event-log/README.md, 1).
    public var recordedAt: Date
    /// The time zone it was recorded in, which decides its day for good.
    public var zone: String
    /// On a retraction, the row it retracts; `nil` otherwise.
    public var retracts: UUID?
    /// The one column that may be edited in place.
    public var note: String = ""
}

extension Dose.Draft {
    /// A dose recorded now. Pass `occurredAt` to back-date it.
    public static func record(
        medicine: String, occurredAt: Date? = nil, note: String = "", id: UUID? = nil
    ) -> Self {
        @Dependency(\.date.now) var now
        @Dependency(\.timeZone) var timeZone
        return Self(
            id: id, medicineID: medicine, occurredAt: occurredAt ?? now, recordedAt: now,
            zone: timeZone.identifier, retracts: nil, note: note)
    }

    /// A retraction of the row `retracted`, recorded now.
    public static func retraction(of retracted: Dose.ID, note: String = "") -> Self {
        @Dependency(\.date.now) var now
        @Dependency(\.timeZone) var timeZone
        return Self(
            id: nil, medicineID: nil, occurredAt: nil, recordedAt: now,
            zone: timeZone.identifier, retracts: retracted, note: note)
    }
}

extension Dose {
    /// The doses in effect: not retractions, and not retracted.
    public static func inEffect(_ db: Database) throws -> [Dose] {
        let retracted = try retractedIDs(db)
        return try Dose.where { $0.retracts.is(nil) && !$0.id.in(retracted) }
            .order(by: \.occurredAt)
            .fetchAll(db)
    }

    /// The ids retracted by a retraction that is itself in effect.
    public static func retractedIDs(_ db: Database) throws -> Set<UUID> {
        let pairs = try Dose.where { $0.retracts.isNot(nil) }
            .select { ($0.id, $0.retracts) }
            .fetchAll(db)
            .compactMap { id, retracts in retracts.map { (id: id, retracts: $0) } }
        return Retractions.retracted(pairs)
    }

    /// Moves a dose to another time: retracts it and records it again, in
    /// the caller's transaction. Returns the new row's id, for undo.
    @discardableResult
    public static func move(_ dose: Dose, to occurredAt: Date, in db: Database) throws -> Dose.ID {
        guard let medicine = dose.medicineID else { throw MoveError.isARetraction }
        @Dependency(\.uuid) var uuid
        let id = uuid()
        try Dose.insert { Draft.retraction(of: dose.id) }.execute(db)
        try Dose.insert {
            Draft.record(medicine: medicine, occurredAt: occurredAt, note: dose.note, id: id)
        }.execute(db)
        return id
    }

    public enum MoveError: Error { case isARetraction }

    /// The calendar its day and time of day are read with: in its own zone,
    /// not the device's current one.
    public func calendar(from base: Calendar) -> Calendar {
        var calendar = base
        calendar.timeZone = TimeZone(identifier: zone) ?? base.timeZone
        return calendar
    }
}

/// The fold (docs/app-tooling/event-log/README.md, 3). A pure function, so
/// it is tested on its own.
public enum Retractions {
    /// The rows no longer in effect, given every retraction as
    /// `(id, retracts)`. A row is in effect unless a retraction in effect
    /// names it. No order is needed: a retraction names only a row that
    /// existed when it was written, so chains never loop.
    public static func retracted(_ retractions: [(id: UUID, retracts: UUID)]) -> Set<UUID> {
        let retractionsOf = Dictionary(grouping: retractions, by: \.retracts)
        var inEffect: [UUID: Bool] = [:]
        func isInEffect(_ row: UUID) -> Bool {
            if let known = inEffect[row] { return known }
            let result = !(retractionsOf[row] ?? []).contains { isInEffect($0.id) }
            inEffect[row] = result
            return result
        }
        return Set(retractionsOf.keys.filter { !isInEffect($0) })
    }
}
```

Screens read `Dose.inEffect`, or a `@FetchAll` with the same `where`,
never `Dose.all`; a history screen that shows retracted rows struck
through reads both. Undoing a move retracts the new row and the
retraction. Every place that groups events by day, or says "this
morning", reads through `calendar(from:)`. Find them: `grep -rn
'startOfDay\|isDateInToday\|dateComponents(' Sources`.

**If the project chose `REAL` timestamps:** the columns are `REAL`, and
the properties `Double` (seconds since 1970) with a computed `Date` beside
them, or a custom `QueryRepresentable` the project writes once and uses on
every timestamp. Not `Date.UnixTimeRepresentation`: it stores whole
seconds.

**4. An existing event table, with real data.** Add what is missing as
new columns and a new table; change nothing that is there.

- `recordedAt` and `zone`, nullable (an older build on another device
  writes rows without them), and not invented for old rows: a guessed
  value presented as data is worse than an honest `NULL`. The Swift
  properties are then `Date?` and `String?`; new rows always set them, and
  a `nil` zone reads with the device's calendar, which is what every row
  did before.
- Retractions in **a table of their own**, since the event table's
  content columns are `NOT NULL` and cannot be relaxed without rebuilding
  it (which, under sync, renames a table). Adding a table is always safe
  under sync. The fold is the same, reading `(id, retracts)` from it.
- The guard triggers (step 5) on both tables, and the new table in
  `SyncEngine(for:tables:)` if the app syncs.

```swift
migrator.registerMigration("v4_doses_append_only") { db in
    // NULL on rows from before this migration: not recorded, not guessed.
    try #sql(#"ALTER TABLE "doses" ADD COLUMN "recordedAt" TEXT"#).execute(db)
    try #sql(#"ALTER TABLE "doses" ADD COLUMN "zone" TEXT"#).execute(db)
    try #sql(
        """
        CREATE TABLE "doseRetractions" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "retracts" TEXT NOT NULL,
            "recordedAt" TEXT NOT NULL,
            "zone" TEXT NOT NULL,
            "note" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
        ) STRICT
        """
    ).execute(db)
    try #sql(
        #"CREATE INDEX "index_doseRetractions_on_retracts" ON "doseRetractions"("retracts")"#
    ).execute(db)
    try installDoseGuards(db)
}
```

Then find every `UPDATE` and `DELETE` of the table in the app's code
(`grep -rn --include='*.swift' -E '\.(update|delete|upsert)\b|UPDATE "doses"|DELETE FROM "doses"' .`)
and turn each into an insert: a retraction, or a retraction and a new row.

**5. The guard triggers**, made on every connection, the preview and test
databases included, and by the migration that creates the table (on a new
database the table does not exist yet when `prepareDatabase` runs):

```swift
configuration.prepareDatabase { db in
    // Only a running SyncEngine registers it otherwise; the triggers call it.
    db.add(function: SyncEngine.$isSynchronizing)
    if try db.tableExists("doses") { try installDoseGuards(db) }
}

/// Refuses changes to the log from the app's own code: it is append-only
/// (docs/app-tooling/event-log/README.md, 3 and 5). Temporary, so made on
/// every connection; a column added later joins the `UPDATE OF` list.
func installDoseGuards(_ db: Database) throws {
    try db.execute(sql: """
        CREATE TEMPORARY TRIGGER IF NOT EXISTS "doses_noUpdate"
        BEFORE UPDATE OF "medicineID", "occurredAt", "recordedAt", "zone", "retracts"
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
```

- **The `UPDATE OF` list is every column except `id` and the mutable
  note.** Leaving out `id` lets SQLiteData's `UPDATE … SET id = id`
  through; leaving out the note is what makes it editable. A project that
  freezes the note too adds it to the list.
- **If the table has exactly one foreign key**, the delete guard refuses
  only while the parent exists, or the row has none (a retraction), so
  SQLiteData's cleanup after a server reference violation, and a cascade,
  can delete it:

  ```sql
  WHEN NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()
    AND (OLD."medicineID" IS NULL
      OR EXISTS (SELECT 1 FROM "medicines" WHERE "id" = OLD."medicineID"))
  ```
- **An app that never syncs**, and never will, may make the triggers
  permanent in the migration instead. The `WHEN` clause then has nothing to
  call: drop it, and the `add(function:)`.

**If the project kept edit in place** (step 2): no guard triggers. The
one write that moves a time changes `occurredAt` and nothing else, and
`recordedAt` is never in an `UPDATE`. Rows the person wrote may be
deleted; imported rows are refused in the write (`guard` and throw), not
only hidden in the UI. Undo restores a deleted row with its `id`.

**If the project chose compensating operations:** that is a domain design,
not a schema convention. Write it down in the project's own docs, with
each operation's other side, keep the rows append-only as above, and
order operations with a hybrid logical clock (README 6).

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
  every event; append-only, so a mistake is corrected by a retraction row
  and only the note is ever edited; enum values never `CHECK`ed; nothing
  sync forbids. Deviations are in `docs/data-model.md`.
```

**9. Record it** in `app-tooling.toml`:

```toml
[patterns.event-log]
params = { timestamps = "text", corrections = "append-only", mutable = ["note"] }
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
  - `Draft.record` with `\.date.now` and `\.timeZone` overridden stores
    both, and `recordedAt` and `occurredAt` equal the overridden now;
  - the fold, as a pure function: a retraction retracts its target; a
    retraction of that retraction brings the target back; a third level
    retracts it again;
  - moving a time leaves three rows (the original, its retraction, the new
    one), of which `inEffect` returns only the new one, with the note
    carried over;
  - a retraction inserted before its target: the target, inserted after,
    is never in effect;
  - the `CHECK`s refuse a row that is half event, half retraction;
  - an `UPDATE` of a content column and a `DELETE` fail, an `UPDATE` of
    the note and `UPDATE … SET "id" = "id"` (what SQLiteData runs before
    its first upload) succeed, and with a foreign key, deleting the parent
    cascades. That the sync engine's own writes pass is seen only in a
    synced build: the flag it sets is not public;
  - an event recorded at 01:00 on 1 November in `Asia/Tokyo` is on 1
    November read through `calendar(from:)` with a base calendar in
    `Europe/Amsterdam`, where it is still 31 October;
  - a row with an enum value this build does not know decodes (as
    unknown), rather than failing the fetch;
  - with definitions: two versions at the same `editedAt` and an older one
    give exactly one current version, whichever was inserted first.

  `\.timeZone` and `\.uuid` have no test value: a test that records
  without overriding them fails with "has no test
  implementation", which is the point.

  `make test` passes, and its output names these tests: a filter that
  matches nothing also passes.
- **A synced build**, by the person: after the signed build first starts
  sync, the app's log shows no `SchemaError` ("Could not synchronize data
  with iCloud"), and a dose recorded on one device appears on the other
  with the same `recordedAt` and `zone`. Read the log with `/usr/bin/log`,
  not `log` (a zsh builtin that prints nothing).
