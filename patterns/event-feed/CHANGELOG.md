# event-feed changelog

## Unreleased

First version, documents only: how an app feeds its events to a shared
timeline through app-utils' `EventFeed` (0.6.0). A pure projection of the
events in effect into `FeedEvent`s from frozen columns only, read back
from the store; `add(inEffect:)` after every write and at launch;
`retract`, `replace` and `restore` only from the call sites that remove,
after the store's write; a settings diagnostic over `differences(inEffect:)`
that acts only when the owner presses and offers no retraction over an
empty projection; the App Group on the iOS target
only; no writer on the group from a scratch database, and none without
the entitlement; `docs/feed.md` from `feed-template.md`. Never a schema
change in the app, a Mac entitlement, or a retraction by set difference.
Walked through against a scratch copy of one app; not yet applied to a
project.

A project taking it: follow `apply.md`. The Mac side is not yet verified;
a later entry will say what a Mac target adds.
