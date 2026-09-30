# TestFlight as the way the iOS apps are distributed

**In progress** on the `testflight` branch, as `patterns/testflight`; this
item goes when it has been verified by a real upload.

**Idea.** One pattern for archiving and uploading to TestFlight, applied to
every project with an iOS app, in place of installing from Xcode.

What is known so far:

- Build numbers: `git-commit-stamp`'s `<count>.<dirty>` is already an
  acceptable, rising `CFBundleVersion`. The upload should refuse a dirty
  build (`.1`).
- Per project it will need the team id, bundle id, scheme, and an App Store
  Connect API key, which must stay out of the repository.
- Shape: a Makefile fragment (`mk/testflight.mk`) plus an
  `ExportOptions.plist`, imported by peru like the other patterns.
