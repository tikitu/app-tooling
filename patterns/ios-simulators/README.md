# ios-simulators

Simulators the project owns, by names no Xcode release changes: one on the
newest iOS, and one on the iOS the phone runs. After an Xcode update,
`make ios-sims`, and simulator testing works again.

> **Draft.** Applied and verified in one project; the shape is settled, the
> details (defaults, how the phone's runtime is chosen) are open. See
> "Open questions".

## The problem

Simulator testing breaks with every Xcode update, and fails in a way that
reads as "this machine cannot test":

- **Device names come and go with runtimes.** A Makefile that says
  `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'` works until the
  newest runtime has no "iPhone 17 Pro" (iOS 27's does not), and then
  xcodebuild lists every device it could not use. The tempting conclusion —
  for a person or an agent — is that simulators are unavailable here, and
  testing is skipped, when the fix was a different name.
- **A name alone means the newest iOS.** `name=X` is `name=X,OS=latest`, so
  a simulator on an older runtime is never found by name, however exactly it
  is spelled.
- **The phone is usually a version behind.** The newest simulator says
  little about the iOS the app actually runs on.
- **Unsigned simulator builds do not open.** A build with
  `CODE_SIGNING_ALLOWED=NO` installs, and then the simulator refuses to
  launch it: "Application failed preflight checks". (The starter's
  `docs/ios.md` describes `ios-build` this way.)

## What it does

`mk/ios-simulators.mk`, included from the project's Makefile, gives:

- **`make ios-sims`**: deletes and recreates two simulators — `<App>` on the
  newest installed iOS (simctl's default when no runtime is named), and
  `<App> Phone OS` on `IOS_PHONE_RUNTIME`. Safe to rerun; rerun after an
  Xcode update.
- **`IOS_SIM_BUILD_FLAGS`**: build for `generic/platform=iOS Simulator`,
  signed to run locally (`CODE_SIGN_IDENTITY=-`). A build needs no simulator
  to exist, and the result launches.
- **`IOS_SIM_UDID`**: a shell snippet for the project's own targets that
  looks `IOS_SIM` up by name and sets `$UDID`, or fails with
  "run make ios-sims". Targets use `-destination "id=$UDID"`, which works on
  any runtime.

The project keeps its own `ios-build`, `ios-test`, `ios-run`; they use these
pieces. `apply.md` gives the target bodies.

## Why this shape

- **Names the project owns** are the stable part. Xcode's device names,
  runtimes and defaults all move; a simulator called `MyApp` does not.
- **Recreate rather than reconcile.** Simulators hold nothing worth keeping,
  so deleting and creating is simpler and more predictable than working out
  which existing device to reuse. An earlier version searched installed
  devices for a match (a script choosing by runtime and name); it worked,
  but was more machinery than the problem needed.
- **The phone's runtime is a parameter, set by hand.** It changes when the
  phone updates, a few times a year. Reading it from the phone at build
  time (`devicectl`) needs the phone awake and nearby, and there is often no
  simulator runtime for the phone's exact point release anyway (no 26.6
  runtime for a phone on 26.6.2), so a person chooses the nearest.

## What it asks of a project

- An iOS app built with `xcodebuild` from make targets.
- `IOS_SIM_NAME` (usually the app's name) and, for the second simulator,
  `IOS_PHONE_RUNTIME`.

It does not install runtimes: `xcodebuild -downloadPlatform iOS`, or Xcode ›
Settings › Components. Nor does it clean up old simulators
(`xcrun simctl delete unavailable`).

## Files

Imported by peru, never edited in a project:

- `mk/ios-simulators.mk`

## Open questions

- Should `IOS_PHONE_RUNTIME` be derived (newest installed runtime with the
  phone's major version) with the hand-set value as an override?
- Default `IOS_SIM_TYPE`: an iPhone that every current runtime supports is
  a moving target too; perhaps the default should be "first iPhone type the
  runtime supports".
- Should the fragment also provide `ios-test-all` (run a project target on
  each of `IOS_SIMS`), or leave that to the project?
- The starter's `docs/ios.md` describes `ios-build` with
  `CODE_SIGNING_ALLOWED=NO`; once this is released the starter should take
  the pattern.
