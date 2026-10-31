# event-log changelog

## Unreleased

First version, documents only: conventions for an app whose data is a
record of what happened. The event row (a UUID `TEXT` key, `occurredAt`
and `recordedAt`, a stored `zone` that decides the event's day, a note);
timestamps as SQLiteData's default ISO-8601 text; corrections append-only,
by retraction rows, folded out on read, with `TEMPORARY` guard triggers
that let the sync engine through and leave the note editable; editable
definitions as an identity table plus versions, the latest `editedAt`
winning; enum values never `CHECK`ed; and what SQLiteData's CloudKit sync
forbids. Drawn from six apps that had each decided these differently; the
owner decided the timestamp encoding and the correction model on
2026-10-31. The Swift in `apply.md` was compiled and its tests run against
sqlite-data 1.12.1 outside any app; the pattern has not yet been applied
to a project.

A project taking it: follow `apply.md`, which starts by asking whether the
tables hold real data (change the creating migration in place if not; add
a migration and a retractions table if so).
