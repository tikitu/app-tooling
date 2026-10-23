# Driving the app from a script

The app can be driven with no clicks and no change of focus. This is how a
change gets *verified* rather than merely compiled, and it is why `AppModel`
exists at all.

```sh
make run-scratch                    # scratch data, accepting commands, in the background
scripts/send-commands.sh '{"commands":[{"add":{"title":"Buy milk"}}]}'
make screenshot                     # build/window.png, by window id
```

## The invariant

**Every button, key and menu item performs an `AppCommand` through
`AppModel.perform(_:)`, and so does the command inbox.** A script therefore
exercises the same code a key press does. A control that does its work itself
is a bug, because it is a path no script can reach — and a path no script can
reach is a path nobody checks.

`perform` is `async`, so a command can wait for what it needs (Touch ID, a
dialog, another process) and still report its outcome. Controls call
`attempt(_:)`, which starts the command at once and returns its task; a
command that does not wait has finished before `attempt` returns, so a
button behaves as if it were synchronous. While one command waits, others
can run: a command that waits says what happens to a second one meanwhile
(refusing it as "busy" is the usual answer).

The deliberate exception is *form state*: typing into the add field, and the
Show Done toggle, write their values directly, as any form does. What
*commits* is a command (`add`), and `configure` is the scripted way to set the
remembered options.

## Where it is enabled, and where it is not

| | accepts commands | database | settings |
|---|---|---|---|
| `make run-scratch` (`--commands <dir> --scratch-database`) | yes | scratch file under the app's `tmp` | the `org.example.starter.scratch` defaults suite |
| `make run`, `make run-background`, or the installed app | **no** | the real one | the real defaults |

`send-commands.sh` refuses rather than timing out when the app is running on
its real data. `make scratch-reset` throws the scratch data away.

## The transport

The command inbox is app-tooling's `command-inbox` pattern:
`docs/app-tooling/command-inbox/guide.md` has how a command file reaches
the app and its result comes back, and the inbox's own commands (`pause`,
`snapshot`; this app gives the inbox no way to draw its windows, so
`snapshot` fails here). This app's values:

- The inbox is `~/Library/Caches/Starter-scratch/Commands/`, which
  `make run-scratch` passes as `--commands` and creates. It is outside the
  app's container on purpose: a terminal without Full Disk Access that
  touches another app's container raises a privacy prompt on the screen of
  whoever is using the machine. A sandbox temporary exception in
  `StarterMac.entitlements` opens it to the app.
- The notification is `org.example.starter.commands`.
- `scripts/send-commands.sh` waits up to 60 s for the result.

## The file format

```json
{
  "id": "optional, echoed back into the result",
  "commands": [
    { "add": { "title": "Buy milk" } },
    { "add": { "title": "Call the plumber" } },
    { "setDone": { "items": ["Buy milk"], "done": true } }
  ]
}
```

A command is an object with **exactly one key**, its name. Decoding is strict:
an unknown command, an unknown field, or more than one key is an error rather
than something ignored, so a typo cannot quietly do nothing.

`CommandFileTests` decodes every JSON example in this file verbatim, so if the
format changes and this document does not, the test fails.

### Referring to an item

By its title, matched exactly. A title no item has, or one that more than one
item has, is an error: a script that meant one item must never act on
another.

### The commands

| Command | Fields | Does |
|---|---|---|
| `configure` | `showsDone` | Sets remembered options. Absent is left alone. |
| `add` | `title` | Adds an item at the end and selects it — typing into the add field and pressing Return. An empty title is an error. |
| `select` | `items` | Replaces the list's selection — a click. |
| `setDone` | `items`, `done` (optional, default `true`) | Marks the items done or not done — Return on the list. |
| `delete` | `items` | Deletes the items — ⌫ on the list. |

```json
{
  "commands": [
    { "configure": { "showsDone": false } },
    { "select": { "items": ["Call the plumber"] } },
    { "setDone": { "items": ["Call the plumber"], "done": false } },
    { "delete": { "items": ["Buy milk"] } }
  ]
}
```

## The result file

```json
{
  "requestID" : "the id from the request, if it had one",
  "completed" : [
    { "command" : "add", "message" : "added 'Buy milk'" }
  ]
}
```

On failure the run stops there and `error` is present:

```json
{
  "completed" : [],
  "error" : "delete failed: no item 'Buy mlik'"
}
```

## Seeing what happened

Commands change state; they do not describe the screen. `make screenshot`
captures the window by id, so nothing is activated and no pointer moves.
`scripts/window-id.swift` refuses when more than one process has a window —
an old copy still running is where stale screenshots come from.

Keys can be pressed without focus too: `scripts/send-keys.swift <pid> down
right return` posts them to the process. See `docs/keyboard.md`.
