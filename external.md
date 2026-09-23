# What lives outside this repo

Some of the setup belongs to other people, and this repo points at it
instead of copying it. This page lists those pieces and says briefly how to
get each one.

## Point-Free Way skills

The `pfw-*` skills are Point-Free's guidance for their own libraries, and
they need a Point-Free subscription. It's not strictly necessary to use these
skills, but recommended if you can afford the subscription.

With a subscription, install their command-line tool from Homebrew. Recent
Homebrew ignores third-party taps until you trust them, so first
`brew trust --formula pointfreeco/tap/pfw` (just this formula, not the whole
tap), then `brew install pointfreeco/tap/pfw`. Then run `pfw install`. It
opens a browser login if it needs one, and installs the skills for every
agent tool it finds (`--tool claude` limits it to one). Run it again from
time to time to pick up new versions.

The libraries themselves (SQLiteData, Dependencies, CustomDump and the rest)
need no setup: SwiftPM fetches them at the versions pinned in each project's
`Package.resolved`.

If you don't have a subscription, the libraries are themselves well-documented.
Use the local checkout provided by SwiftPM (which includes their documentation
sources) and direct access to the source code to use them more effectively.

## SwiftUI Pro

The `swiftui-pro` skill is Paul Hudson's, published as a Claude Code plugin at
[github.com/twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill).
Inside Claude Code, add that repo as a plugin marketplace with
`/plugin marketplace add twostraws/SwiftUI-Agent-Skill`, then install
`swiftui-pro` from it.

## macOS Design

The `macos-design` skill comes from
[github.com/ceorkm/macos-design-skill](https://github.com/ceorkm/macos-design-skill).
It's a plain skill directory, so cloning it into `~/.claude/skills/macos-design`
is the whole installation. It's written as much for web and Electron as for
SwiftUI, so its CSS-flavoured advice needs translating.

## Command-line tools

Xcode 26 or later provides everything the build needs: `swift`, `swift
format`, `codesign`, `notarytool` and the simulators. Beyond that, two tools
come from Homebrew: `ast-grep` for the lint rules, and `xcodegen` to generate
the iOS project in repos that have an iOS app. The GitHub CLI, `gh`, is only
needed to publish a release. Each `Makefile` checks for what it uses and
says what to install if something is missing.

## An Apple Developer account

This is only needed for signing, notarizing, CloudKit sync and installing
on a real iPhone. Day-to-day Mac work gets by with ad-hoc signing. The
account-side steps (App IDs, iCloud containers, provisioning profiles) are
done by hand in the developer portal; each project's `plans/sync.md` records
which ones it needed.
