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
  grep -rn --include='*.swift' -E '"(occurred|happened|done|measured|recorded|logged|written|edited)At"|(occurred|happened|done|measured|recorded|logged|written|edited)_at|"zone"' .
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
    try installAppendOnlyGuards(db)
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
- Both tables in `appendOnlyTables` (step 5), and the new table in
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
    try installAppendOnlyGuards(db)
}
```

Then find every `UPDATE` and `DELETE` of the table in the app's code
(`grep -rn --include='*.swift' -E '\.(update|delete|upsert)\b|UPDATE "doses"|DELETE FROM "doses"' .`)
and turn each into an insert: a retraction, or a retraction and a new row.

**5. The guard triggers**, made on every connection, the preview and test
databases included, and by the migration that creates the table (on a new
database the table does not exist yet when `prepareDatabase` runs), and
again at the end of any migration that adds a column to one:

```swift
configuration.prepareDatabase { db in
    // Only a running SyncEngine registers it otherwise; the triggers call it.
    db.add(function: SyncEngine.$isSynchronizing)
    try installAppendOnlyGuards(db)
}

/// An append-only table: its name, the columns that may be edited in place,
/// and, for a table with exactly one foreign key, that key's column and the
/// table it points at.
struct AppendOnlyTable {
    var name: String
    var mutable: Set<String> = ["note"]
    var parent: (column: String, table: String)? = nil
}

/// Every append-only table (docs/app-tooling/event-log/README.md, 3).
let appendOnlyTables = [
    AppendOnlyTable(name: "doses"),
    // A table with exactly one foreign key names it:
    // AppendOnlyTable(name: "doses", parent: (column: "medicineID", table: "medicines")),
    AppendOnlyTable(name: "doseRetractions"),
]

/// Refuses changes to the log from the app's own code (README, 3 and 5), on
/// each append-only table that exists yet. Temporary, so made on every
/// connection; a migration that adds a column calls it again at its end.
func installAppendOnlyGuards(_ db: Database) throws {
    let notSync = "NOT sqlitedata_icloud_syncEngineIsSynchronizingChanges()"
    let refuse = "BEGIN SELECT RAISE(ABORT, 'the log is append-only: write a retraction'); END"
    for table in appendOnlyTables where try db.tableExists(table.name) {
        // Read from the table, never typed out: SQLite accepts a column that
        // does not exist in `UPDATE OF`, and then guards nothing.
        let guarded = try db.columns(in: table.name).map(\.name)
            .filter { $0 != "id" && !table.mutable.contains($0) }
            .map { "\"\($0)\"" }.joined(separator: ", ")
        // SQLiteData's cleanup after a server reference violation deletes a
        // row whose parent is gone; a row with no parent stays guarded.
        let parentGone = table.parent.map { parent in
            """
            AND (OLD."\(parent.column)" IS NULL OR EXISTS (
              SELECT 1 FROM "\(parent.table)" WHERE "id" = OLD."\(parent.column)"))
            """
        } ?? ""
        let name = table.name
        try db.execute(sql: """
            DROP TRIGGER IF EXISTS temp."\(name)_noUpdate";
            DROP TRIGGER IF EXISTS temp."\(name)_noDelete";
            DROP TRIGGER IF EXISTS temp."\(name)_noReplace";
            CREATE TEMPORARY TRIGGER "\(name)_noUpdate"
              BEFORE UPDATE OF \(guarded) ON "\(name)" FOR EACH ROW
              WHEN \(notSync) \(refuse);
            CREATE TEMPORARY TRIGGER "\(name)_noDelete"
              BEFORE DELETE ON "\(name)" FOR EACH ROW
              WHEN \(notSync) \(parentGone) \(refuse);
            -- `INSERT OR REPLACE` of an existing id deletes the row without
            -- firing the delete trigger: such an insert does nothing instead.
            CREATE TEMPORARY TRIGGER "\(name)_noReplace"
              BEFORE INSERT ON "\(name)" FOR EACH ROW
              WHEN \(notSync) AND EXISTS (SELECT 1 FROM "\(name)" WHERE "id" = NEW."id")
              BEGIN SELECT RAISE(IGNORE); END;
            """)
    }
}
```

- **Every column but `id` and the mutable ones is guarded**, read from
  the table rather than typed out. A typed list is how a guard silently
  guards nothing: SQLite accepts a column that does not exist in `UPDATE
  OF`, so a list copied from another table, or a column renamed in the
  example, leaves the real column open. Leaving out `id` lets SQLiteData's
  `UPDATE … SET id = id` through; leaving out the note is what makes it
  editable.
- **Every append-only table is in `appendOnlyTables`**, the retractions
  table of step 4 included.
- **Never `INSERT OR REPLACE`, `.insert(or: .replace)` or an upsert** on
  an append-only table. A REPLACE over an existing id deletes the old row
  without firing its delete trigger (unless `PRAGMA recursive_triggers` is
  on) and inserts the new one, which is not an update: it rewrites an event
  past both guards. Imports, which may meet a row they wrote before, use
  `INSERT OR IGNORE` (`.insert(or: .ignore)`). The `_noReplace` trigger is
  the backstop: an insert of an id that is already there does nothing,
  whatever its conflict clause.
- **A table with exactly one foreign key** names it in `parent`, so that
  SQLiteData's cleanup after a server reference violation, and a cascade,
  can delete a row whose parent is gone; a row with no parent (a
  retraction) stays guarded.
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
- **What sync would refuse.** On the same database:

  ```sh
  sqlite3 -readonly "$DB" <<'SQL'
  WITH RECURSIVE
    tables(name) AS (SELECT name FROM sqlite_schema
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'),
    edge(src, dst) AS (SELECT t.name, fk."table" FROM tables t, pragma_foreign_key_list(t.name) fk),
    reach(start, node, depth) AS (SELECT src, dst, 1 FROM edge
      UNION SELECT r.start, e.dst, r.depth + 1 FROM reach r JOIN edge e ON e.src = r.node
      WHERE r.node != r.start AND r.depth < 32)
  SELECT 'unique: ' || t.name || '.' || il.name
    FROM tables t, pragma_index_list(t.name) il WHERE il."unique" AND il.origin != 'pk'
  UNION ALL
  SELECT DISTINCT 'cycle: ' || start FROM reach WHERE node = start
  UNION ALL
  SELECT 'on delete: ' || t.name || '.' || fk."from" || ' ' || fk.on_delete
    FROM tables t, pragma_foreign_key_list(t.name) fk
    WHERE fk.on_delete IN ('RESTRICT', 'NO ACTION')
      AND (SELECT count(*) FROM pragma_foreign_key_list(t.name)) = 1
  UNION ALL
  SELECT 'reserved: ' || t.name || '.' || c.name
    FROM tables t, pragma_table_info(t.name) c
    WHERE c.name IN ('creationDate', 'creatorUserRecordID', 'etag',
      'lastModifiedUserRecordID', 'modificationDate', 'modifiedByDevice',
      'recordChangeTag', 'recordID', 'recordType')
  UNION ALL
  SELECT 'primary key: ' || t.name || ' has '
      || (SELECT count(*) FROM pragma_table_info(t.name) WHERE pk > 0) || ' columns'
    FROM tables t WHERE (SELECT count(*) FROM pragma_table_info(t.name) WHERE pk > 0) != 1
  UNION ALL
  SELECT 'name: ' || t.name || ' contains a colon' FROM tables t WHERE instr(t.name, ':') > 0;
  SELECT 'tables checked: ' || count(*) FROM sqlite_schema
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%';
  SQL
  ```

  prints only the `tables checked:` line, its count the number of names
  `.tables` lists other than `grdb_migrations`. Each other line is
  something `SyncEngine` refuses when it is created: a unique index, a
  foreign-key cycle of any length (a table referencing itself is the
  shortest), `ON DELETE RESTRICT` or `NO ACTION` on a table with exactly
  one foreign key, a reserved column name, a primary key of other than one
  column, a `:` in a table name. A `primary key` line for a table the app
  does not sync can be ignored.

  **What it cannot check**, because the list of synced tables is in Swift,
  not in the database: that every table the app means to sync is in
  `SyncEngine(for:tables:)`, and that every foreign key of a synced table
  points at a synced table. Check both by hand against that call. A clean
  result here does not cover them.
- **Tests**, in the project's test target, against the in-memory database
  that runs the real migrator:
  - `Draft.record` with `\.date.now` and `\.timeZone` overridden stores
    both, and `recordedAt` and `occurredAt` equal the overridden now
    (make it a whole number of milliseconds: the stored text keeps no
    finer, and `Date()` makes the comparison fail);
  - the fold, as a pure function: a retraction retracts its target; a
    retraction of that retraction brings the target back; a third level
    retracts it again;
  - moving a time leaves three rows (the original, its retraction, the new
    one), of which `inEffect` returns only the new one, with the note
    carried over;
  - a retraction inserted before its target: the target, inserted after,
    is never in effect;
  - the `CHECK`s refuse a row that is half event, half retraction;
  - for each append-only table, **every content column in turn**: an
    `UPDATE` setting it to itself fails. Take the columns from the table,
    not a list in the test, so a column added later is covered:

    ```swift
    @Test(arguments: ["doses", "doseRetractions"])
    func everyContentColumnIsGuarded(table: String) throws {
        let columns = try db.read { try $0.columns(in: table).map(\.name) }
        let content = columns.filter { $0 != "id" && $0 != "note" }
        #expect(!content.isEmpty)
        for column in content {
            #expect(throws: (any Error).self, "\(table).\(column)") {
                try db.write { try $0.execute(sql: #"UPDATE "\#(table)" SET "\#(column)" = "\#(column)""#) }
            }
        }
        try db.write { try $0.execute(sql: #"UPDATE "\#(table)" SET "note" = 'edited', "id" = "id""#) }
        #expect(throws: (any Error).self) { try db.write { try $0.execute(sql: #"DELETE FROM "\#(table)""#) } }
    }
    ```

    (the note and `SET "id" = "id"`, what SQLiteData runs before its first
    upload, succeed; a `DELETE` fails). With a foreign key, deleting the
    parent cascades. That the sync engine's own writes pass is seen only in
    a synced build: the flag it sets is not public;
  - `INSERT OR REPLACE` with an existing id leaves the row as it was, and
    `INSERT OR IGNORE` of an existing id does nothing;
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
