# Starter

A Mac app. Describe it here: what it is for, in a paragraph.

Mac only, built with SwiftPM (no Xcode project), on the Point-Free libraries.
Data lives in a SQLite file in the app's container, settings in its user
defaults.

## Build and run

```sh
make run          # build and launch
make test         # the test suite
make install      # copy to /Applications
make help         # everything else
```

Needs macOS 26 and a Swift 6.2 toolchain (Xcode). There is no Xcode project:
SwiftPM builds it and `build.sh` bundles and signs it, ad-hoc by default.

Read [PLAN.md](PLAN.md) next, then [PROGRESS.md](PROGRESS.md).

## Where this came from

The structure (a SwiftPM-only Mac build driven by `make` and `build.sh`, the
sign-notarize-staple release pipeline, and making a new app by copying and
running one rename script) is due to Thomas Ptacek's
[swiftui-app](https://github.com/tqbf/swiftui-app) template. It has been
reworked for a particular way of working: the Point-Free libraries, pinned
dependencies, a command inbox so an agent can drive and check the app
without taking focus, keyboard-first lists, and lint rules for mistakes that
fail silently.
