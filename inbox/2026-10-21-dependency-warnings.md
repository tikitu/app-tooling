# Warnings from dependencies and Xcode, not from our code

From the warning-free survey (hub B6BE5YV, TW1T37T), 2026-10-21, Xcode 27.1
/ Swift 6.4. Three warnings showed up in nearly every project and came from
somewhere other than its own code. Each one either has a supported switch
that removes its cause, or comes from a dependency that has fixed it in a
newer release. None of these fixes hides a warning: `LM_FILTER_WARNINGS`,
`-w` and log filtering were ruled out.

## 1. `IssueReportingTestSupport`: `ld: warning: building for macOS-12.0 …`

**Problem.** Every test build that links `IssueReportingTestSupport` (through
`DependenciesTestSupport` and the like) prints, under SwiftPM and xcodebuild
alike:

```
…/swift-issue-reporting/Package.swift: IssueReportingTestSupport-product: ld: warning: building for macOS-12.0, but linking with dylib '@rpath/Testing.framework/Versions/A/Testing' which was built for newer version 14.0
(the same for libXCTestSwiftSupport.dylib; iOS-simulator 15.0 vs 17.0)
```

swift-issue-reporting declares the product `.dynamic`, so it is linked as its
own dylib at the package's own deployment target (macOS 10.15, raised to
Xcode 27's floor of 12), against Testing.framework, which is built for 14.
Raising the platforms in our own packages changes nothing. No release
changes this: 1.11.0 through 2.1.2 (the latest) declare the same platforms
and the same dynamic product. Upstream has no issue filed about it.

**What worked.** Upstream's own switch, added in xctest-dynamic-overlay
1.11.0 (PR #183, for Wasm) and in every swift-issue-reporting 2.x: with
`OMIT_DYNAMIC_TEST_SUPPORT` set in the environment, the product's type is
left to SwiftPM, so it is linked statically into the test bundle, which is
built at our own deployment target. Proved in throwaway clones:

- stochastic_self's `Pings` (xctest-dynamic-overlay 1.11.0), `swift build
  --build-tests`: two `ld` warnings without it, none with it; `swift test`
  passes (28 + 25 tests).
- The starter's `StarterKit` (swift-issue-reporting 2.1.1), `xcodebuild test`
  on an iOS 26 simulator: two `ld` warnings without it, none with it; tests
  pass.
- In both, a probe test checked that `reportIssue` still reaches Swift
  Testing once the library is static (IssueReporting finds the test-support
  functions with `dlsym`, so a missing library would not fail the build):

  ```swift
  @Test func reportIssueReachesSwiftTesting() {
    withKnownIssue { reportIssue("probe") }
  }
  ```

  It passed "with 1 known issue" both ways, and would fail if no issue were
  recorded.
- SwiftPM honours a change to the variable without a clean: unsetting it
  brought the warning back on the next build.

**To roll out.** Export it from the build entry point, so that every
`swift build`, `swift test` and `xcodebuild` run there sees it:
`export OMIT_DYNAMIC_TEST_SUPPORT := 1` in the Makefile (the starter's
`Makefile`, or `mk/app-tooling.mk` if every project should get it), or
`OMIT_DYNAMIC_TEST_SUPPORT = "1"` under `[env]` in `mise.toml`.

- **Builds started from Xcode.app are not covered** (not tested): the IDE
  does not inherit a shell's environment, so they should still warn. Only
  command-line and agent builds are proved.
- **Pins.** Needs xctest-dynamic-overlay ≥ 1.11.0 or swift-issue-reporting
  2.x. Already there: everything on swift-issue-reporting 2.x, stochastic_self
  (1.11.0), say-out-loud (1.13.1). **Needs a deliberate pin bump**:
  TarPit's root package (xctest-dynamic-overlay 1.8.0), lacebark's
  `Bookmarks` (1.8.1) and flummoxagon's `FlummoxagonKit` (1.8.1).
- Open, the user's call: also file an upstream issue asking for a real fix
  (e.g. a higher deployment target for the test-support product).

## 2. App Intents: `Metadata extraction skipped, no AppIntents.framework dependency found`

**Problem.** Every xcodebuild of an app, and of a package's test bundles
(the starter's `CoreTests`/`UITests`), runs the ExtractAppIntentsMetadata
step and prints this warning.

**What worked.** `LM_SKIP_METADATA_EXTRACTION = YES`, as stochastic_self did
on its app targets without App Intents (its commit 2c737b4). It is not a
filter: in swift-build, `AppIntentsMetadataTaskProducer.generateTasks()`
returns no tasks when it is set (`Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift`,
and the macro is declared in `SWBCore/Settings/BuiltinMacros.swift`), so
`appintentsmetadataprocessor` never runs. Proved on the starter's
`StarterKit`, `xcodebuild … LM_SKIP_METADATA_EXTRACTION=YES test` on an iOS
26 simulator: no `appintentsmetadataprocessor` invocation at all, 0 warnings,
tests pass. `LM_FILTER_WARNINGS` (what ReadingRecord found) only passes
`--quiet-warnings` to a step that still runs.

**To roll out.** Set it **only on targets with no App Intents**: on a target
that has them it would drop their metadata without any error, and the
intents would vanish from Shortcuts and Siri. So: per target in the project
spec (xcodegen `settings`, Tuist `settings`) for app and test targets without
intents; for a package-scheme xcodebuild (no target settings to put it in),
on the command line, with a comment that it must go when a package gains an
App Intent. Projects whose packages declare App Intents (stochastic_self's
`Extensions`) must not pass it on the command line.

## 3. SQLite.swift: `'v4' is deprecated: watchOS 9.0 is the oldest supported version`

**Problem.** TarPit only. SQLite.swift's own `Package.swift` declares
`.watchOS(.v4)`; TarPit pins 0.15.4 (`from: "0.15.0"`).

**What worked.** Nothing applied yet. SQLite.swift 0.17.0 (2026-10-20)
declares `.watchOS(.v9)`, `.macOS(.v12)` ("Update minimum deployment targets
to match Xcode 27"); 0.15.5 and 0.16.0 still have `.v4`. The bump is within
TarPit's existing requirement but **changes the SQLite library behind
TarPit's live archive**: the embedded SQLite becomes 3.53.4, the package
moves to Swift 6 language mode, and how connections close changed (#1361,
#1373). It is also **source-breaking** for TarPit: in a throwaway clone,
`swift package update sqlite.swift` moved only `sqlite.swift` 0.15.4 →
0.17.0 (and dropped the `swift-toolchain-sqlite` 1.0.4 pin), and the build
then failed at `Sources/TarPit/FavouritesClient.swift:214`,
`catch let Result.error(_, code, _) where code == SQLITE_CONSTRAINT`:
`Result.error` is now `(message:, code:)`, with no statement. That `catch` is
on the path that stores posts, so the bump is the user's call, and wants
TarPit's own checks on a copy of the archive, not only a clean build. Until
then it is an upstream warning, fixed upstream, waiting on that bump.
