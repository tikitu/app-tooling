# privileged-helper changelog

## v0.1.0 (2026-10-05)

First version, documents only: a launchd daemon in the bundle, registered
with `SMAppService.daemon`, running one command as root for the app over
XPC; each side checking the other's signature and team; registering only
from `/Applications`; Touch ID before the risky direction; the password
dialog as the fallback. Worked out in a menu-bar app that switches one
system setting: dev builds, then a notarized release installed by a
Homebrew cask, where the helper was allowed once and ran as root, and a
later build ran without asking again. The snippets in `apply.md` were
compiled together, outside that app. Not tried: a sandboxed app.
