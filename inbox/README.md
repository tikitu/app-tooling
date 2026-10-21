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

- [2026-10-20 Which patterns an app takes by default](2026-10-20-default-patterns.md)
- [2026-10-20 After the TestFlight device guard: an empty list, and a development app](2026-10-20-testflight-guard-followups.md)
- [2026-10-21 Warnings from dependencies and Xcode, not from our code](2026-10-21-dependency-warnings.md)
- [2026-10-21 The command inbox as a pattern, not only starter files](2026-10-21-command-inbox-as-a-pattern.md)
- [2026-10-21 The command inbox and scratch data trip the "data from other apps" prompt](2026-10-21-command-inbox-outside-container.md)
