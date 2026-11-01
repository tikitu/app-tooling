# event-feed

For an app that records what happened (the
[`event-log`](https://github.com/tikitu/app-tooling/blob/main/patterns/event-log/README.md)
kind) and whose events should also appear on one shared timeline, read by
another app of the same developer. The app projects the events it has in
effect into a **feed**: an append-only SQLite file that it alone writes,
in an App Group container shared by every feeding app and the reader. The
reader opens each feed read-only and imports it.

Documents only. The file format, the writer and the reader are app-utils'
`EventFeed` library, 0.6.0 or later
([`docs/EventFeed.md`](https://github.com/tikitu/app-utils/blob/0.6.0/docs/EventFeed.md));
this pattern is how an app adopts it without putting its own data at risk.

## The problem

Each event app keeps its own log, in its own container. A question that
crosses apps ("did I sleep worse the weeks I missed the cream?") needs the
events side by side, and no app can see another's store. The obvious
fixes each lose data or invite it:

- **The reader opens the other apps' databases.** It cannot (sandbox), and
  if it could, it would depend on every app's schema forever.
- **Each app exports what changed since last time.** A watermark records
  what was meant to be sent, not what arrived; a reset or a bug on either
  side silently drops rows.
- **The feed mirrors the store, and the writer deletes from it whatever
  the store no longer has.** A store that is empty for an innocent reason
  (a reinstall, a store that has not finished loading, a projection bug)
  becomes a mass deletion in every reader.
- **Rows that change.** A feed row edited in place cannot be told apart
  from the original by a reader that already imported it, and two devices
  writing the same event in different states disagree forever.

## What it does

- **The app projects, the library appends.** A pure function turns the
  app's rows into `FeedEvent`s: the events *in effect now*, each with an
  id derived from its source row and every value it carries.
  `FeedWriter.add(inEffect:)` appends those the feed lacks, after every
  write and at launch. Adding is idempotent, so running it too often costs
  nothing.
- **Nothing in the feed changes.** Rows are only appended. Only values the
  source freezes at insert go into a row; a value the app edits in place
  is either part of the row's identity (an edit is then a retraction of the
  old row and a new row) or not in the feed. The same source state gives
  the same bytes on every device, so two devices feeding one app need no
  coordination.
- **A removal is retracted only where the app removes it.** The call site
  that deletes, edits a frozen value or undoes a delete tells the writer
  (`retract(removed:…)`, `replace(removed:with:…)`, `restore(_:…)`). The
  writer **never retracts by comparing the feed with the store**; the
  library has no API that does. A projection bug can fail to add; it can
  never remove.
- **A missed removal is reported, never repaired unattended.** A settings
  diagnostic shows `differences(inEffect:)`: rows the feed has in effect
  that the store does not, and the reverse. The owner retracts or restores
  them explicitly.
- **Scratch data never reaches the shared container.** A run on a scratch
  database writes its feed beside the scratch data. Without the App Group
  entitlement the app writes no feed and says so in settings: there is no
  fallback directory.
- **`docs/feed.md`** in the project says what it feeds: the kinds, the
  subjects, the payload keys, the names, and where it differs.

## What it asks of a project

- app-utils' `EventFeed` product, pinned at 0.6.0 or later.
- The App Group entitlement on the **iOS** target, with the group id the
  reader and every feeding app share.
- A model with one write path (a `perform`, or whatever the project calls
  the one function every mutation goes through), so "after every write"
  is one call site.
- A launch flag or setting that says the database is scratch, such as
  [`scratch-data`](https://github.com/tikitu/app-tooling/blob/main/patterns/scratch-data/README.md)'s
  `--scratch-database`.

## What it does not do

- **No schema change in the adopting app.** The projection reads the
  tables the app already has. If it seems to need a new column, stop and
  ask; that is a different change.
- **No retraction by set difference**, ever, in the app or the library.
- **Nothing mutable in the feed.** Not a note edited in place, not a name
  (names go in `feed_subjects` as append-only versions), not anything
  device-specific or time-of-import.
- **No Mac entitlement yet.** On macOS the App Group container behaves
  differently (it is documented to return a URL whether or not the app is
  entitled, and `group.` ids are not described there), so a Mac app gets
  the group only after access from both the reader and a writer has been
  verified on scratch builds. Until this pattern's changelog says that has
  happened, feeds are written on iOS only.
- **No reader.** Reading feeds is the reader app's business, with
  `FeedReader` and `Retractions.retracted`.

## Known limits

- **A removal whose feed call never ran** (the app died between its own
  write and the feed write) leaves the old row in effect. The launch
  reconcile only adds, so it does not notice; the diagnostic does.
- **An undo on another device.** Each device's writer sees only its own
  feed. A delete made on device 1 and undone on device 2 appends nothing
  on device 2, and the reader still folds device 1's retraction. The app's
  own store still shows the event; the timeline does not. Undo on the
  device that deleted.
- **Dates must be passed as the store holds them.** Ids derive from dates
  rounded to whole milliseconds. SQLiteData's `Date` text encoding
  truncates, so a `Date` that has not been through the store can round to
  the millisecond above the stored one and derive a different id; the next
  reconcile then adds a second row. Build every `FeedEvent` from rows read
  back from the store.
