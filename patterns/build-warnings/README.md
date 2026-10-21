# build-warnings

Two warnings that nearly every project's build prints, from a dependency
and from Xcode rather than from the project's code, removed at their cause.
Neither is hidden: no `-w`, no `LM_FILTER_WARNINGS`, no filtering of logs.
A build that is warning-free stays one where a new warning gets noticed.

`mk/build-warnings.mk`, included from the `Makefile`, does both parts on
every `make` run.

## 1. `IssueReportingTestSupport`: `ld: warning: building for macOS-12.0 …`

```
…/swift-issue-reporting/Package.swift: IssueReportingTestSupport-product: ld: warning: building for macOS-12.0, but linking with dylib '@rpath/Testing.framework/Versions/A/Testing' which was built for newer version 14.0
```

(and the same for `libXCTestSwiftSupport.dylib`; on the iOS simulator, 15.0
against 17.0). It shows in every test build that links
`IssueReportingTestSupport`, directly or through `DependenciesTestSupport`
and the like, under SwiftPM and xcodebuild alike.

swift-issue-reporting declares that product `.dynamic`, so it is linked as
a dylib of its own, at the package's own deployment target, against a
Testing.framework built for a later one. Raising the project's `platforms`
changes nothing, and no release of the package has changed this.

**The fix** is the package's own switch: with `OMIT_DYNAMIC_TEST_SUPPORT`
in the environment, its manifest leaves the product's type to SwiftPM, which
links it statically into the test bundle, at the project's deployment
target. The fragment exports it. `reportIssue` still reaches Swift Testing
and XCTest: IssueReporting finds the test-support functions by name at run
time, in whatever image holds them. `apply.md` has a test that proves it.

It needs xctest-dynamic-overlay 1.11.0 or later, or any swift-issue-reporting
2.x; on older versions the variable does nothing.

## 2. App Intents: `Metadata extraction skipped, no AppIntents.framework dependency found`

Every xcodebuild of an app, and of a package's test bundles, runs Xcode's
App Intents metadata step, which warns when there is nothing to extract.

**The fix** is the build setting `LM_SKIP_METADATA_EXTRACTION = YES`, which
makes Xcode plan no metadata task for the targets it is set on:
`appintentsmetadataprocessor` does not run for them (`generateTasks()` in swift-build's
[`AppIntentsMetadataTaskProducer.swift`](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift)
returns nothing when it is set). (`LM_FILTER_WARNINGS`, the other setting that removes the
warning, only quiets a step that still runs.)

**The danger.** On a target that has App Intents, the skip drops their
metadata without any error or warning, and the intents disappear from
Shortcuts, Siri and Spotlight. A comment beside the setting would not
protect against that, so the fragment checks: on every `make` run,
`scripts/check-app-intents-skip.sh` fails the run, naming the files, if
`LM_SKIP_METADATA_EXTRACTION` appears anywhere in the project (Markdown
aside) while any Swift file mentions `AppIntents`, `AppIntent`,
`AppShortcutsProvider`, `AppEntity` or `AppEnum`. So the day a project
adopts App Intents, its next `make` of anything stops until the skip is
removed.

The check is whole-project, deliberately: it does not work out which target
a Swift file belongs to, so a project with App Intents anywhere cannot use
the skip anywhere. Intents often live in a local package and reach the app
through it, where a check of the app target's own sources would miss them. Mentions in comments count. Both err on the side of
keeping intents.

## What it asks of a project

- A `Makefile` at the root that includes the fragment. A project driven by
  something else (mise, a script) sets the variable and runs the check
  there (`apply.md`).
- For part 1, xctest-dynamic-overlay ≥ 1.11.0 or swift-issue-reporting 2.x.
- For part 2, only in a project with no App Intents: the setting, in the
  Xcode project spec and on the command line of package-scheme xcodebuilds.

## What it does not do

- **Builds started from Xcode.app** do not read the `Makefile`, so part 1
  does not reach them, and they still print the `ld` warning. Part 2 does
  when the setting is in the project spec, but the check runs only with
  `make`: a project that adopts App Intents while working only in Xcode
  finds out at its next `make`.
- **Intents that come from a dependency** (a package that ships its own
  App Intents) are not seen by the check, which reads only the project's own
  files. Such a dependency arrives through a reviewed pin change.
- Other warnings from dependencies (a manifest's deprecated platform
  version, say) are fixed by updating the dependency, if a release has fixed
  them, or not at all.
