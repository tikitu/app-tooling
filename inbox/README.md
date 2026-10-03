# Inbox

Things another project found out that might belong here, not yet made into
a pattern, a rule or a change to the starter. One file per item, named
`YYYY-MM-DD-short-name.md`, so that an agent in another project can add one
without having to fit it into anything.

## Adding an item

From any project, when something turns out not to be specific to that app,
write a file here with:

- **Problem.** What went wrong or was missing, concretely: the symptom, and
  what it cost. Name the project and date; they are provenance, removed when
  the item is promoted.
- **What worked**, if something did: the change, and where to see it (a
  commit in that project).
- **Idea**, if nothing has been tried yet.

Rough is fine. The point is not to lose it.

## Promoting an item

Make it a pattern (see [`patterns/README.md`](../patterns/README.md)), a
lint rule, or a change to the starter, whichever fits; delete the item in
the same commit. What was not done goes into a new item, not left behind in
the old one. An item that turns out not to generalise is deleted with a
line in the commit message saying why.

## Items

- [2026-09-28 Keep a log of device installs](2026-09-28-device-install-log.md)
- [2026-09-28 TestFlight as the way the iOS apps are distributed](2026-09-28-testflight.md)
- [2026-10-01 Refuse development installs on TestFlight devices](2026-10-01-testflight-only-devices.md)
- [2026-10-02 Where a release's notes file goes: not in `dist/`](2026-10-02-release-notes-file.md)
