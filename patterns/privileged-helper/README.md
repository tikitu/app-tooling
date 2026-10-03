# privileged-helper

A Mac app that has to run one command as root, without asking for a
password every time: a small launchd daemon inside the app's bundle,
registered with `SMAppService.daemon`, allowed once by the person in System
Settings, and asked over XPC to do that one thing.

## The problem

The easy way to run something as root from an app is AppleScript's
`do shell script … with administrator privileges`. It uses macOS's own
password dialog, so the app never sees the password, and it needs no setup.
But it asks **every time**. AppleScript was once documented to remember the
authorisation for five minutes; on macOS 26 a second switch within a minute
asked again. And it takes a password only, never Touch ID. For an app whose
whole point is a quick switch, that is the app not working.

The other ways each cost more than they look:

- **A sudoers rule** for the one command: small, but it is a file in `/etc`
  that the app cannot install or remove by itself, and that nothing in
  System Settings shows.
- **`sudo` on a pseudo-terminal**, with the password typed into the app's
  own field: the app then holds a real secret, and all the code around it.
- **`SMJobBless`**: deprecated since macOS 13.

`SMAppService.daemon` is Apple's current way. The person approves once, in
System Settings → General → Login Items & Extensions, where they can also
see and revoke it.

## What it does

- **A helper that does one thing.** An executable target in the app's
  package, bundled as `Contents/MacOS/MyAppHelper`, with its launchd plist
  in `Contents/Library/LaunchDaemons`. Its XPC protocol has one method, for
  the one command, taking only what the command needs (a `Bool`, say),
  never a path or an argument string. launchd starts it, as root, when the
  app connects; it exits ten seconds after its last request, so the next
  one runs whatever build is installed.
- **Each side checks the other's signature.** The helper accepts only the
  app's identifier, the app talks only to the helper's; in a Developer ID
  build, both also require the same team. The requirement is built at run
  time from the process's own team, so a dev build signed ad hoc still
  works on its own machine.
- **It registers only from `/Applications`.** A copy anywhere else (a
  build directory, Downloads) can be rewritten by anything running as the
  user. Nor from a translocated copy (below).
- **Asking the owner before the risky direction.** Where one direction of
  the command can do harm if done by mistake (keeping a Mac awake until its
  battery is flat, say), the app asks for Touch ID first (`LAContext`,
  `.deviceOwnerAuthentication`, which falls back to the password), and
  remembers it for a few minutes. The safe direction asks nothing. This is
  a guard against accidents, not a security boundary: the check is in the
  app, so anything that can pass the helper's signature check can skip it.
  Say so where it is documented, so nobody mistakes one for the other.
- **The password dialog stays, as the fallback.** Without the helper, or
  before it is allowed, the app does what it did before. Installing the
  helper is something the person chooses, from the app.
- **A deadline on every call.** launchd does not fail a connection to a
  helper it cannot start (below), so the app gives up after five seconds
  and says what to do.
- **A pretend helper in scratch mode.** `HelperClient` is a dependency;
  scratch mode's registers at once and needs no approval, and the tests'
  fails any call not overridden. No script or test ever registers a real
  daemon.
- **Diagnostics that could have found the problems below.** What
  `SMAppService` reports, by name, where the app is running from, and
  `launchctl print system/<label>` (no root needed), in a bug report the
  app can copy.

## Traps

Every one of these failed silently, or looked like something else.

- **A daemon never registered reports `.notFound`**, not `.notRegistered`:
  Background Task Management has no record of it. Read at its word, it
  says the helper is missing from the app. Check the bundle yourself, and
  treat `.notFound` with the files present as "never registered".
- **macOS asks only once.** "App Background Activity … Do you want to allow
  this?" appears when the record is *created*. Unregistering keeps the
  record, and registering again asks nothing, whether the prompt was
  allowed or dismissed. From every state but "never registered", the app
  opens Login Items itself (`SMAppService.openSystemSettingsLoginItems()`).
  (`sudo sfltool resetbtm` clears the records, every app's, which is no
  fix for one.)
- **`register()` throws when it has succeeded.** For a daemon not yet
  allowed, it registers it, asks, and *then* throws "Operation not
  permitted". Read the status after a throw, and carry on if it is
  `.requiresApproval`.
- **A helper launchd cannot start makes XPC wait for ever.** launchd
  retries every ten seconds ("service inactive") and the call never
  returns. The case found: launchd's job still pointed at the record of an
  earlier ad-hoc build (`Unable to resolve <uuid> … Code=-95`, then `Could
  not find and/or execute program`), though a notarized build had
  registered since. `sudo launchctl bootout system/<label>` cleared it.
- **A bundle's path ends in "/".** `Bundle.main.bundleURL` is a directory
  URL, so its path is `/Applications/MyApp.app/`; `URL(filePath:
  "/Applications/MyApp.app")` has no slash. Compared as they are, the app
  is never in Applications. Trim the slash, and test it.
- **App Translocation.** A quarantined app that Finder has not moved runs
  from a read-only copy under `…/AppTranslocation/<random>/`, so
  `Bundle.main` is not where the app is. A quarantine flag set by hand
  translocated the app even after a Finder move; a Homebrew cask install
  was quarantined properly and not translocated.
- **SMAppService's status has no readable description**: it prints as
  `SMAppServiceStatus(rawValue: 1)`. Name the cases yourself for logs.

## What was found about trust

Tried with a helper that ran one fixed command:

- An ordinary program connecting to the helper was refused ("Dropping
  check-in message due to code signing requirement").
- A program signed ad hoc with the app's identifier was accepted: with ad
  hoc signing the identifier is all there is, and anything can claim it.
  That is why only `/Applications` registers, and why a release build
  requires the team.
- A replaced helper binary, signed ad hoc as the helper, was **refused by
  launchd** (`OS_REASON_CODESIGNING | Launch Constraint Violation`) and
  never ran. macOS ties the daemon to the code that was registered.
- A new Developer ID build found the helper already allowed, and ran it
  at once: the approval follows the helper's identifier and team, not one
  build, so an update does not ask again. For ad-hoc builds, re-registering
  a rebuilt app asked for approval again.

## What it asks of a project

- **No App Sandbox**, as tried. A sandboxed app would at least need a
  `mach-lookup` exception for the helper's service; that has not been
  tried.
- **An async `perform`.** Touch ID, the password dialog and the XPC reply
  all wait, so `AppModel.perform(_:)` and the command inbox become
  `async`. The starter's are synchronous.
- **Signing inside out.** The helper is signed on its own, with its own
  identifier, before the app's signature seals it: in `build.sh` (ad hoc)
  and in `make sign` (Developer ID, hardened runtime, timestamp; notarizing
  refuses nested code without them).
- **Developer ID, for anyone but the author.** Ad hoc works on the machine
  that built it, and only from `/Applications`.
- A Mac app built from a `build.sh` that assembles the bundle, as the
  starter's does. Requires the `pattern-imports` pattern, to import these
  documents.

It does not carry code: the helper's protocol, its command and the app's
words for it are different in every app. `apply.md` has the shape to
follow, in pieces.

It does not cover a helper that has to take arguments from the app, or
more than one command. Every argument is something a caller that passes
the signature check can choose; keep it to one command and a yes/no if
you can, and think hard before going further.

## Files

None imported but these documents. `apply.md` has the steps;
`CHANGELOG.md` what changed between releases.
