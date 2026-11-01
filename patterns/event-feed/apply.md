# Applying event-feed

Read [`README.md`](README.md) first, and app-utils'
[`docs/EventFeed.md`](https://github.com/tikitu/app-utils/blob/0.6.0/docs/EventFeed.md),
which is the authority on the API and the file. This file is how to make an
existing app a feed writer. The examples use `MyApp`, a source `myApp`,
an `events` table and an `activities` table; use the project's.

Three things this pattern never does, whatever the project looks like:
**no change to the app's schema**, **no App Group entitlement on a Mac
target**, and **no retraction derived by comparing the feed with the
store**. If a step seems to need one of them, stop and ask the user.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|event-feed-docs`,
  and `app-tooling.toml` has `[patterns.event-feed]`.
- **Partly there:**

  ```sh
  grep -rn --include='*.entitlements' -A3 'application-groups' .
  grep -rn -E 'application-groups|ApplicationGroups|group\.' --include='project.yml' .
  grep -rn --include='*.swift' -E 'import EventFeed|FeedWriter|FeedEvent|containerURL\(forSecurityApplicationGroupIdentifier' .
  ```

  An App Group already on the iOS target may be the app's own (for a
  widget); the feed's group is a second one, added beside it. A
  `FeedWriter` that is created somewhere is the pattern half done: check
  each step below against it rather than adding a second.
- **Something else doing this job:** an export the reader imports (a
  file, a share sheet, a Shortcut), or a sync between the two apps. Tell
  the user what exists and ask before replacing it; this pattern does not
  remove it.
- **The parts the steps build on:**

  ```sh
  grep -rn --include='*.swift' -E 'func perform\(|func (record|delete|retime|restore|undo|update|edit)[A-Z(]' .
  grep -rn --include='*.swift' -E 'scratch-database|isScratch|scratchDatabase' .
  ```

  The first finds the model's one write path and the call sites that
  remove or replace an event. The second finds how the app knows it is on
  scratch data. A project without either has to get one first
  ([`scratch-data`](https://github.com/tikitu/app-tooling/blob/main/patterns/scratch-data/README.md)
  for the second); ask.

## Parameters

| Parameter | Example | Where to find it |
|---|---|---|
| iOS bundle id | `com.example.MyApp` | `project.yml`, `PRODUCT_BUNDLE_IDENTIFIER` of the iOS app target. The feed file is named by it, so a scratch bundle id writes a separate file |
| Source name | `myApp` | new: the app's name in lower camel case, no `/`. It goes into every feed id, so it never changes once fed. Ask the user if the app has more than one plausible name |
| Feed App Group id | `group.com.example.feed` | the reader's documentation, or ask the user. One id for the reader and every feeder; not the app's own group |
| The events-in-effect query | `Event.inEffect` in `Sources/Core/Queries.swift` | the query the app's history or "latest" view is built on, with retracted or deleted rows already left out. It is the events the app holds as having happened, not what one screen shows: a screen that hides a deleted definition's events is not it (step 4) |
| The frozen columns of each fed table | `events`: `activityID`, `occurredAt`, `recordedAt`; not `notes` | the table and every `UPDATE` of it (step 3) |
| Removing and replacing write paths | `Event.delete`, `Event.retime`, `Event.restore`, and the undo handlers that call them | Detect, above: every call that deletes a row, edits a frozen column, writes a retraction row, or undoes one of those. **Undo and redo handlers** (`registerUndo` closures) often write to the store directly rather than through the one write path: list them too |
| Names | `activities.name`, versioned by `activityVersions.editedAt` | a definitions table with an edit time the app stores (the event-log pattern's versions) |
| Opt-in, and its default | none: always on; or a toggle, on by default | ask the user. A feed carries health or private data the reader then syncs; the user decides whether that is a toggle |
| The scratch signal | `--scratch-database` | Detect, above |

## Steps

**1. Import the documents.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|event-feed-docs: docs/app-tooling/event-feed/
```

and beside the other rules:

```yaml
rule event-feed-docs:
    pick: [patterns/event-feed/README.md, patterns/event-feed/apply.md, patterns/event-feed/CHANGELOG.md, patterns/event-feed/feed-template.md]
    export: patterns/event-feed
```

Then `uvx peru@1.3.5 sync`.

**2. Add the library**, pinned, to the package that holds the model:

```swift
.package(url: "https://github.com/tikitu/app-utils", exact: "0.6.0"),
```

and to the target that holds the projection (step 4):

```swift
.product(name: "EventFeed", package: "app-utils"),
```

If the package already depends on app-utils at an older version, raise
it to `0.6.0` and run the project's tests: other app-utils products move
with it. Commit `Package.resolved`.

**3. Decide what each fed row carries.** For each event table, list its
columns and, for each, whether the app ever changes it after insert
(`grep -rn 'UPDATE\|\.update\|\.upsert' --include='*.swift'` over the
model, and the table's `Draft` uses). Then:

- **Frozen** (written once): it may go into the row, as `occurredAt`,
  `recordedAt`, `zone`, `subject` or a payload value.
- **Edited in place, but only by a deliberate correction** (a retime of
  `occurredAt`): it goes in, and the call site that edits it calls
  `replace` (step 7). An edit is then a new feed row.
- **Edited in place casually** (a note, a comment): **out**, unless the
  user decides it is part of identity. Ask; record the answer in
  `docs/feed.md`.
- **The time zone:** the column if the app stores one, else `nil`. Never
  `TimeZone.current`.

Choose each table's `kind` (`activity.done`, `dose.taken`: noun, dot,
past participle), its `subject` (the stable id of the thing it is about,
never its name) and the payload keys (string values only). Write them
into `docs/feed.md` (step 10) now; the rest of the steps implement it.

**4. The projection**, a pure function next to the model, with no
database access of its own:

```swift
import EventFeed

extension Event {
    /// This event as a feed row. Pass the row as read back from the store:
    /// the id derives from its dates at the millisecond the store keeps.
    func feedEvent() -> FeedEvent {
        FeedEvent(
            source: "myApp", table: "events", rowID: id.uuidString,
            kind: "activity.done", subject: activityID.uuidString,
            occurredAt: occurredAt, recordedAt: recordedAt, zone: nil)
    }
}
```

Its inputs are rows fetched through the events-in-effect query, so a
deleted or retracted row is never projected. "In effect" means the events
the app holds as having happened, not what one screen shows: if the app
soft-deletes a definition (an activity) and keeps its events, those events
stay in the projection unless the user decides that deleting a definition
removes its events, in which case the definition's delete (and its undo)
is a removing call site in step 7. Ask; write the answer in
`docs/feed.md`. Tests (Swift Testing, in the
model's test target):

- a row projects to the expected kind, subject and payload;
- the id is stable: the same row twice gives the same id;
- changing each frozen column changes the id; changing a column left out
  (a note) does not;
- a row inserted into an in-memory store and **read back** projects to the
  same id however often it is read and written back (use an `occurredAt`
  with a fractional millisecond, `Date(timeIntervalSince1970:
  1_793_000_000.4965)`, which is where an in-memory value and the stored
  text disagree);
- a retracted or deleted row is not in the projection of the store;
- through the model (step 6 and 7): with a `FeedWriter` on a temporary
  directory injected, record, retime, delete, undo the delete and undo the
  retime through the app's own calls, then `FeedReader` that file: the
  events not in `Retractions.retracted` are exactly the projection of the
  store, a retime added three rows, and `differences(inEffect:)` is all
  empty. So the model must accept its writer from outside (an initialiser
  parameter or a dependency), not only build it itself.

**5. Open the writer** after the app's bootstrap has opened and migrated
its database, in the object that owns the model, once:

```swift
import EventFeed

/// Where this run's feed goes, or why there is none.
enum FeedDestination {
    case directory(URL)
    case none(reason: String)

    static func current(scratchDatabase: URL?, enabled: Bool) -> FeedDestination {
        guard enabled else { return .none(reason: "Turned off in Settings.") }
        // A scratch run feeds beside its scratch data, never the shared group.
        if let scratchDatabase { return .directory(scratchDatabase.deletingLastPathComponent()) }
        #if os(iOS)
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.example.feed")
        else { return .none(reason: "This build has no feed App Group entitlement.") }
        return .directory(group)
        #else
        return .none(reason: "Feeds are written on iOS only for now.")
        #endif
    }
}
```

```swift
let writer: FeedWriter?
switch FeedDestination.current(scratchDatabase: launch.scratchDatabase, enabled: settings.feedEnabled) {
case .directory(let base):
    do {
        writer = try FeedWriter(base: base, source: "myApp", bundle: Bundle.main.bundleIdentifier!)
    } catch {
        writer = nil
        feedStatus = .failed(error.description)   // shown in settings (step 8)
    }
case .none(let reason):
    writer = nil
    feedStatus = .off(reason)   // shown in settings (step 8)
}
```

- **Never a fallback directory.** If the container is `nil` the app writes
  no feed and settings say why. A feed written somewhere the reader does
  not look is a feed the owner believes exists.
- **A scratch database never opens the group container**, however it was
  launched. Check the scratch signal before `containerURL` is called, as
  above.
- **An iOS app with no scratch mode** (it always opens its one database)
  needs none for this pattern: on a simulator its data is scratch anyway,
  and an unsigned simulator build has no entitlement, so `containerURL`
  is `nil` and it writes no feed. The model test in step 4 is where the
  feed is exercised. Do not add a scratch mode to the iOS app as part of
  this pattern.
- **No toggle, or toggle on**: the writer starts. **Toggle off**: it is
  not created; rows already fed stay in the feed.
- A `FeedWriter` that fails to open (`FeedError`) is shown in settings
  with its description, and the app carries on. A feed is never a reason
  for the app's own write to fail.

**6. Add after every write and at launch.** At the end of the model's one
write path, after the store's write has committed, and once after the
writer opens:

```swift
func reconcileFeed() {
    guard let writer else { return }
    do {
        let events = try database.read { try Event.inEffect.fetchAll($0) }
        try writer.add(inEffect: events.map { $0.feedEvent() })
        for version in try database.read({ try ActivityVersion.all.fetchAll($0) }) {
            try writer.name(subject: version.activityID.uuidString, name: version.name, since: version.editedAt)
        }
        writer.post()
    } catch {
        feedStatus = .failed(String(describing: error))   // shown in settings
    }
}
```

A `perform` that returns from each case of a `switch` has no single
end: call it from a `defer` at the top, or from the function that calls
`perform`, so no case is missed. Undo and redo handlers that write
directly to the store call it too, after their write. This is all the launch reconcile does: it adds. It never retracts.
Names are fed only from a stored edit time (`since`); if the app keeps
names without one, leave names out and record that in `docs/feed.md`
rather than inventing a time.

**7. Retract, replace and restore only at the removing call sites.** For
each write path in the parameter list, **read the affected row from the
store before the write**, let the write commit, then tell the writer:

| The app's write | Feed call, after the write |
|---|---|
| deletes an event, or writes a retraction row for it | `writer.retract(removed: old.feedEvent().id, recordedAt: …, zone: …)` |
| corrects an event by a retraction row plus a new row, in one write | `writer.replace(removed: old.feedEvent().id, with: new.feedEvent(), recordedAt: …, zone: …)`, `new` read back after the write |
| edits a frozen column (a retime) | `writer.replace(removed: old.feedEvent().id, with: new.feedEvent(), recordedAt: …, zone: …)`, where `new` is the row **read back after the write** |
| undoes a delete, or writes a retraction of a retraction | `writer.restore(restored.feedEvent().id, recordedAt: …, zone: …)` |
| undoes a record | `retract`, as a delete |
| undoes a retime | `replace`, from the current row to the earlier one, as a retime |

- `recordedAt` and `zone` are the retraction row's own where the app
  writes one (an event-log app does); otherwise the moment of the removal
  (`@Dependency(\.date.now)` or the app's clock) and `nil` unless the app
  stores a zone.
- After the store's write, not before: a feed retraction for a write
  that then failed would hide an event the app still has, and `add` never
  undoes it.
- Then the step 6 reconcile runs as usual (it is the end of `perform`).
- No other code calls these three. In particular nothing iterates the
  feed or the store looking for what to retract.

**8. Settings: status and diagnostic.** One section, "Timeline feed":

- the status: on, writing to the group; on, scratch, writing beside the
  scratch data (show the path); off, and the reason from step 5; or the
  last error from step 6;
- a **Check** button that runs `writer.differences(inEffect:)` over the
  same projection and shows the three counts (`onlyInFeed`,
  `onlySupplied`, `suppliedButRetracted`);
- for a non-zero `onlyInFeed`, a button that retracts exactly those ids,
  behind a confirmation that says how many; for `suppliedButRetracted`,
  one that restores them; for `onlySupplied`, a button that runs the
  step 6 reconcile. Nothing runs unless the owner presses it.
- **No retract button when the projection is empty.** An empty store is
  the innocent case the pattern guards against (not loaded yet, a
  reinstall, a sync still arriving): every fed row is then `onlyInFeed`,
  and one confirmation would retract the whole feed. Show the counts and
  say why the button is missing.

**9. Mac targets: nothing yet.** A Mac target gets neither the
entitlement nor a writer on the group (step 5's `#else`). A Mac scratch
run may feed beside its scratch data. The changelog will say when the
Mac side is verified and what to add.

**10. The group, iOS only, and `docs/feed.md`.** Find how the iOS app
target gets its entitlements: the app target only, not a widget or other
extension that shares the app's own group. If `project.yml` sets
`CODE_SIGN_ENTITLEMENTS` to committed files (often one per configuration,
such as a sync and a no-sync variant), add the group to **each** of those
files, beside any group already there:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.example.feed</string>
</array>
```

If it uses XcodeGen's `entitlements:` key instead:

```yaml
    entitlements:
      path: App/MyApp.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.example.feed
```

keeping any group the target already has. Never the Mac target's
entitlements (step 9). Then
copy `docs/app-tooling/event-feed/feed-template.md` to `docs/feed.md` and
fill it in from step 3. In `AGENTS.md`, one line:

```markdown
* **The app feeds the shared timeline** (`docs/feed.md`, app-tooling's
  `event-feed` pattern): the feed is append-only and only frozen columns
  go in; retract, replace and restore only from the call sites that
  remove; never retract by comparing the feed with the store; never open
  the group container on scratch data.
```

**11. Record it** in `app-tooling.toml`:

```toml
[patterns.event-feed]
params = { source = "myApp", group = "group.com.example.feed", opt_in = "no", scratch = "--scratch-database" }
# Kinds and deviations are in docs/feed.md.
```

## Verify

- **Tests:** `make test` (or the project's equivalent) exits 0 and its
  output names the step 4 tests. A filter that matches nothing also
  passes, so check the names are there.
- **The feed exists and is well formed.** Have the step 4 model test
  leave its feed at a known path (or run a scratch build that writes
  beside its scratch data), then read it with `sqlite3 -readonly` (never
  the library, never read-write):

  ```sh
  feed="<scratch dir>/Feeds/com.example.MyApp.sqlite"
  sqlite3 -readonly "$feed" "SELECT key, value FROM feed_meta ORDER BY key"
  sqlite3 -readonly "$feed" "SELECT rowid, id, kind, subject, occurred_at, recorded_at, zone, retracts, payload FROM feed_events ORDER BY rowid"
  ```

  `feed_meta` has `schema 1`, the source, the bundle id and the writer
  (`app-utils EventFeed 0.6.0`); the event's row has the kind, subject and
  timestamps you expect. An empty result from the second query is a
  failure, not "nothing recorded": check that the first printed four rows.
- **A retime leaves three rows**: the original, its retraction, and the
  new row, in that order. A delete then appends one retraction; an undo of
  it appends a retraction of that retraction.
- **Byte identity.** Run the projection over the same scratch database
  from two builds (or a test with two `FeedWriter`s) into two directories;
  the rows are identical:

  ```sh
  q="SELECT id, kind, subject, occurred_at, recorded_at, zone, retracts, payload FROM feed_events ORDER BY id"
  diff <(sqlite3 -readonly a/Feeds/com.example.MyApp.sqlite "$q") \
       <(sqlite3 -readonly b/Feeds/com.example.MyApp.sqlite "$q") && echo identical
  ```

  It must print `identical`, and the files must each have rows.
- **No fallback.** Run the iOS app on a simulator unsigned (or any build
  without the entitlement): settings say there is no feed entitlement, and
  no `Feeds/` directory appears in the app's own container
  (`find "$(xcrun simctl get_app_container booted com.example.MyApp data)" -name Feeds`
  prints nothing; check the container path itself printed). A scratch
  build that does write leaves its feed beside the scratch data, and the
  simulator's group container has no feed for it.
- **The entitlement**, on an iOS build that is signed (the person's, if
  the agent's builds are not):

  ```sh
  codesign -d --entitlements - path/to/MyApp.app
  ```

  shows `com.apple.security.application-groups` with the feed group. A
  Mac build shows no feed group.
- **The diagnostic** on the scratch run reports all three counts as 0.
