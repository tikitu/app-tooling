# build-warnings changelog

## v0.5.0 (2026-10-21)

First version. `mk/build-warnings.mk` exports `OMIT_DYNAMIC_TEST_SUPPORT=1`,
which removes swift-issue-reporting's `IssueReportingTestSupport` `ld`
warnings, and on every `make` run calls `scripts/check-app-intents-skip.sh`,
which stops the run while `LM_SKIP_METADATA_EXTRACTION` (the setting that
skips Xcode's App Intents metadata step) and App Intents code are both in
the project. To adopt: follow `apply.md`. It may need a pin bump to
xctest-dynamic-overlay ≥ 1.11.0, and adds the setting only in projects with
no App Intents. Tried on throwaway clones of four existing apps: two
with an xcodegen iOS app, package-scheme tests and swift-issue-reporting
2.x (both parts, and the probe intent that stops `make`), one on
xctest-dynamic-overlay 1.8.0 (the bump to 1.11.0 and the `severity`
parameter), and one whose App Intents live in a package (the check refuses
the skip there).
