# Adding an iOS app

The template is Mac only, but shaped so that an iOS app slots in beside the
Mac one: `Packages/StarterKit` already declares iOS and `make check` already
compiles it for iOS. This is how to add the app itself.

## An iOS-only package, beside the Mac one

`Packages/StarterIOSKit`, declaring `.iOS(.v26)` and nothing else, depending
on `../StarterKit`. Everything iOS-specific lives there: the root view,
anything that imports UIKit, anything only the phone can do. As with the Mac
package, the manifest is the boundary, so nothing needs `#if os(iOS)`
(`rules/platform-conditionals.md`). Anything that can be tested on the Mac
belongs in `StarterKit` and its suite; the iOS package's tests are for what
only iOS can run.

## The Xcode project is generated, and git-ignored

SwiftPM cannot express an iOS app bundle, so there has to be an Xcode
project, but it should be the smallest part of the repo:

- `apps/ios/project.yml` is the source of truth. The app target in it is a
  forwarding shell over a product of `StarterIOSKit`: no logic lives in the
  target.
- XcodeGen generates `apps/ios/Starter.xcodeproj` from it
  (`brew install xcodegen`; `make ios-project`). The `.xcodeproj` — and any
  `Info.plist` or entitlements file generated from the yaml — is
  **git-ignored**. Edit the yaml; never edit the pbxproj.

This keeps project-file merge conflicts out of the repo, and keeps the
Xcode project from quietly accumulating settings nobody can see in review.

In `project.yml`, set the same things the packages spell out:
`SWIFT_VERSION` 6, `SWIFT_STRICT_CONCURRENCY: complete`, and
`SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated` — new Xcode templates default
it to MainActor, which would silently differ from the packages.

## Keep the pins pinned

The generated project resolves packages on its own, and because it is
git-ignored so is its lockfile. Its package graph is exactly
`StarterIOSKit`'s, so `make ios-project` copies that package's
`Package.resolved` into
`apps/ios/Starter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`, and
every `xcodebuild` passes the Makefile's `$(XCODE_FLAGS)`:
`-onlyUsePackageVersionsFromResolvedFile`, and `-skipMacroValidation`, since
`xcodebuild` refuses untrusted package macros and the Point-Free libraries
are full of them (`docs/gotchas.md`).
`check-pins` then compares three lockfiles instead of two, and `update-pins`
updates all three packages.

## Make targets

| Target | Does |
|---|---|
| `ios-project` | `xcodegen generate`, then copy in the lockfile |
| `ios-build` | build for the simulator with `CODE_SIGNING_ALLOWED=NO`, so no provisioning profile is needed |
| `ios-test` | the iOS package's suite on a simulator (`xcodebuild test -workspace Packages/StarterIOSKit`) |
| `ios-run` | install and launch on the booted simulator with `xcrun simctl` |
| `ios-device-build`, `ios-device-run` | sign for real (`-allowProvisioningUpdates`) and install with `xcrun devicectl` |
| `ios-device-which` | which commit the app on the device was built from |
| `ios-clean` | delete the generated project |

## Which commit is on the phone

The Mac build already records its commit (`AppGitCommit` in the bundle's
`Info.plist`, written by `scripts/stamp-git-commit.sh`). The iOS app needs
the same, as a build phase so that installs from Xcode's Run button are
stamped too, and with `CFBundleVersion` set from the commit, since that is
all a phone will report. The pattern is already imported:
`docs/app-tooling/git-commit-stamp/apply.md` has the build phase, the
`ios-device-which` target and the reasons.

`xcrun simctl` drives the simulator without taking focus, as the Mac
targets do; there is no equivalent of `send-keys` for the simulator, so
drive it with the same command inbox.

## Traps

- **Package traits do not reach the Xcode build.** A trait enabled in
  `Package.swift` works for `swift build` and `swift test` and is missing
  from the build through the generated project. Use no package traits;
  anything that builds on only one of the two front ends is not done.
- **A sandboxed Mac app cannot share the iOS app's bundle id.** Once a phone
  has registered the iOS app, a sandboxed Mac bundle with the same id hangs
  before `main()`, with no window, no error and no log. Give the Mac app its
  own id (`…Mac`). The symptom: `make run` succeeds, `pgrep` finds the
  process, and it has no window.
- **`xcrun devicectl device copy from` can leave a 0-byte file.** A failed
  copy does not always fail loudly, and the empty file then reads as missing
  data ("no such table") rather than a failed copy. Check the exit status and
  the size before believing what you pulled.
- **The test scheme's name changes.** A package with one library product has
  a scheme named after the package; with two or more it becomes
  `<Package>-Package`.
