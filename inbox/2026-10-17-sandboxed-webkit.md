# A sandboxed app's WKWebView: an entitlement, and a load that never ends

From Session Sets (abc-irish), 2026-10-17, hub ticket SDG9GRZ.

## Problem

The app renders HTML offscreen in a `WKWebView` and makes a PDF of it. In
the App Sandbox this failed in two silent ways:

1. **The page process never launches without
   `com.apple.security.network.client`**, even for `loadHTMLString` with no
   network use. Tests and scripts run unsandboxed and pass. The only trace
   is WebKit's own log (`WebProcessProxy::didFinishLaunching: Invalid
   connection identifier (web process failed to launch)`).
2. **A page process that dies or never starts is not a failed load.**
   WebKit calls `webViewWebContentProcessDidTerminate` and neither `didFail`
   callback. A load awaited through the navigation delegate waits for ever.
   In abc-irish, the scripted command never returned and the model stayed
   "busy" until a relaunch.

## What worked

- The entitlement, commented with its reason
  (`SessionSetsMac/SessionSetsMac.entitlements`).
- `webViewWebContentProcessDidTerminate` resumes the waiter with an error.
  A lint rule requires it on every `WKNavigationDelegate`:
  `rules/web-process-termination.{yml,md}` and
  `rule-tests/web-process-termination-test.yml` in abc-irish, commit
  d54021b. It could join the starter's rules as is.
- Both traps are in abc-irish's `docs/gotchas.md`, with a third that is
  starter-wide: `Bundle.module` silently falls back to the build folder, so a
  resource missing from the `.app` still loads on the machine that built it.
  To prove the bundle's own copy is used, hide the build folder's
  `*.bundle`s and run.
