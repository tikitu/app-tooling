# command-inbox changelog

## Unreleased

First version, from the starter's command inbox and three apps' copies of
it: the runner and strict decoding as a Swift module the app imports into a
package directory of its choosing, the sender as
`scripts/command-inbox-send.sh` with its parameters as options, `guide.md`.
Beyond the starter's copy: the inbox directory comes from `--commands
<dir>`, outside any container; app commands wait for the app to be ready
(`isReady:`, with a timeout); `pause` and `snapshot` are the inbox's own
commands; a reply can carry structured detail (`state`); the sender reads
the result's `error` key rather than grepping for the word, and can send to
an iOS simulator (`--simulator`).

A project with a copy (from the starter, or another app): follow `apply.md`.
Delete the copy's `CommandInbox.swift`, `AnyKey` and `CommandFile`, move its
decoder onto `StrictCommand`, make its `scripts/send-commands.sh` the
wrapper in step 6, and pass `--commands` from `run-scratch` (step 5; with
the entitlement if the app is sandboxed). Remove any `app-tooling.toml`
table recording the copy.
