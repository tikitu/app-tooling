# A navigation delegate handles the page process dying

**Rule:** `web-process-termination`, in `rules/web-process-termination.yml`,
tested by `rule-tests/web-process-termination-test.yml`

The template has no `WKWebView`; the rule waits for the first one. It cost
an earlier app a hung export.

## The rule

A type that conforms to `WKNavigationDelegate` implements
`webViewWebContentProcessDidTerminate(_:)`, and fails whatever is waiting
on the load.

## Why it fails silently

WebKit draws a page in a separate process. When that process crashes, or
never launches, WebKit calls `webViewWebContentProcessDidTerminate` and
**neither** `didFail` nor `didFailProvisionalNavigation`. Code that waits
for a load (on a continuation resumed from `didFinish`, say) therefore
waits for ever. The app logs nothing at error level, and a scripted command
waiting on it never returns: `send-commands.sh` reports only that no result
came, which reads as "the app is not accepting commands".

## What it cost

An earlier app rendered HTML offscreen to make a PDF. In the App Sandbox
without `com.apple.security.network.client`, the page process never
launched (`docs/gotchas.md`). The first export hung, and left the model's
"exporting" flag set, so every later export was refused as busy until a
relaunch. The cause only showed in WebKit's own log lines
(`WebProcessProxy::didFinishLaunching: Invalid connection identifier`).

## What to do instead

Implement `webViewWebContentProcessDidTerminate(_:)` beside `didFinish`,
and resume the waiter with an error.

## When a finding is not a bug

A navigation delegate that nothing waits on, for a page a person is
looking at, can let WebKit's own reload behaviour stand. Say so with an
`// ast-grep-ignore: web-process-termination` and a comment.

## Known exceptions

None yet.

## What would break the rule

- The method implemented in a separate extension from the conformance: the
  rule reads one declaration at a time, so it flags that. Keep the method
  with the conformance.
- A delegate set through a wrapper that does not conform itself (a closure
  adapter, say) is not seen at all.
