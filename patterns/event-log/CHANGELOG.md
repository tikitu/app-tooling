# event-log changelog

## Unreleased

First version, documents only: conventions for an app whose data is a
record of what happened. The event row (a UUID `TEXT` key, `occurredAt`
and `recordedAt`, a stored `zone` that decides the event's day, a note);
timestamps as SQLiteData's default ISO-8601 text; corrections by editing
in place with `recordedAt` kept; editable definitions as an identity table
plus versions, the latest `editedAt` winning; enum values never `CHECK`ed;
and what SQLiteData's CloudKit sync forbids, with append-only guard
triggers that let the sync engine through. Drawn from six apps that had
each decided these differently. The timestamp encoding and the correction
model are open owner decisions; the README has both options tables. The
Swift and SQL in `apply.md` were compiled and run against sqlite-data
1.12.1 outside any app; the pattern has not yet been applied to a project.

A project taking it: follow `apply.md`, which starts by asking whether the
tables hold real data.
