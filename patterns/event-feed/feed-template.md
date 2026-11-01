# What MyApp feeds to the shared timeline

<!-- Copied from app-tooling's event-feed pattern
(docs/app-tooling/event-feed/feed-template.md). This copy is the project's
own: fill it in and keep it current. Delete this comment. -->

MyApp writes its events to a feed, an append-only file in the App Group
`group.com.example.feed`, as app-tooling's `event-feed` pattern describes
(`docs/app-tooling/event-feed/README.md`). The reader imports it.

| | |
|---|---|
| Source name | `myApp` (never changes: it is in every feed id) |
| Feed file | `<group container>/Feeds/com.example.MyApp.sqlite` |
| Library | app-utils `EventFeed` 0.6.0 |
| Opt-in | no / a toggle in Settings, on by default |
| Platforms | iOS. Mac: not yet (the pattern's changelog says when) |
| Scratch runs | write beside the scratch database, never into the group |
| Code | the projection (`Event.feedEvent()` in …), where the writer opens (…), the settings section (…) |

## Kinds

One row per kind the app writes. `subject` is the stable id of the thing
the event is about; names come from `feed_subjects`.

| Kind | Source table | Subject | `occurred_at` | `recorded_at` | `zone` | Payload keys |
|---|---|---|---|---|---|---|
| `activity.done` | `events` | `activityID` | `occurredAt` | `recordedAt` | none: the app stores no zone | none |

## Identity: what is frozen

The columns each row is built from. Anything the app edits in place is
either part of identity (an edit is a retraction plus a new row) or left
out; say which, and why.

| Table | Column | In the feed? | Why |
|---|---|---|---|
| `events` | `occurredAt` | yes, part of identity | a retime is a `replace` |
| `events` | `notes` | no | edited in place; the owner's decision, date |

## Names

`feed_subjects` versions come from: `activityVersions` (`name`,
`editedAt` as `since`). Or: none, because the app stores no edit time.

## Corrections

The only places that call the writer's corrections:

| App write | Feed call |
|---|---|
| `Event.delete` | `retract(removed:…)`, with the removal time, zone `nil` |
| `Event.retime` | `replace(removed:with:…)` |
| `Event.restore` | `restore(_:…)` |

Nothing else retracts. The settings diagnostic (Settings › Timeline feed)
reports differences and retracts or restores only when the owner presses.

## Deviations

What this app does differently from the pattern, and why. "None" is an
answer.
