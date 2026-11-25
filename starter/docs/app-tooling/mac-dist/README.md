# mac-dist

A release of a Mac app outside the App Store: `git tag vX.Y.Z && make dist`
signs the app with a Developer ID, has Apple notarize it, staples the
ticket, zips it, writes its checksum and checks it as Gatekeeper will; `make
github-release` publishes the zip and checksum as the tag's GitHub release.
Anyone can then download it and open it without being told the app is
damaged or from an unidentified developer.

It is the starter's release pipeline, moved into `mk/mac-dist.mk` so that
apps made from the starter, and apps that copied its `Makefile`, get later
fixes by updating instead of by hand.

## What it prevents

- **A release nobody can open.** Without a Developer ID signature, the
  hardened runtime, a secure timestamp and a notarization ticket, a
  downloaded app is refused by Gatekeeper. Every one of those has to be on
  every executable in the bundle, nested ones included, or notarization
  is refused.
- **A release that does not match a commit.** `make dist` refuses to run
  without an exact `vX.Y.Z` tag at `HEAD`.
- **A zip without the ticket in it.** Notarization takes a zip; stapling
  changes the app; so the distributed zip is a second one, made after
  stapling.
- **Signing with the wrong identity.** A Mac that also holds the team's
  "Apple Distribution" identity (for an iOS app, say) would otherwise be
  asked for that one. `CERT_NAME` names the Developer ID in full.
- **A personal password in the release process.** `make notary-setup`
  takes an App Store Connect team API key, which belongs to no person, has
  no password or phone number, and can be revoked at any time. An Apple
  Account with an app-specific password still works, typed at a prompt.

## What it asks of a project

- A target that builds the app in its release configuration, and one that
  removes earlier builds and `dist/` (`release` and `clean` in the
  starter).
- An exact `vX.Y.Z` tag per release, and a `VERSION` file for builds
  between releases.
- Once per team: a **Developer ID Application** certificate (only the
  Account Holder may create one), and for notarization an App Store Connect
  **team API key** with the **Developer** role. Neither needs an App ID, a
  provisioning profile or an app record in App Store Connect.
- Once per Mac that releases: the certificate with its private key in the
  login keychain, and `make notary-setup`, which stores the API key in the
  keychain under `NOTARY_PROFILE`.
- Xcode or the Command Line Tools (`codesign`, `notarytool`, `stapler`),
  and `gh` for `github-release`.

## Code nested in the app

A helper tool or helper app inside the bundle must be signed first, with
its own identifier, and the app after it: the app's signature seals what
is inside it. The project names a target of its own as
`MAC_DIST_SIGN_NESTED`, which signs each with `$(mac_dist_codesign)`;
[`apply.md`](apply.md) has an example.

## Targets

| Target | Does |
|---|---|
| `dist` | Checks the tag, cleans, builds, signs, notarizes, staples, zips, checksums and verifies. Leaves `dist/<Name>-<version>-macos.zip` and its `.sha256` |
| `verify-release` | The same without the tag check and the clean: `make verify-release VERSION=0.1.0` for a trial. It still uploads the build to Apple |
| `github-release` | The tag's GitHub release, with the zip and checksum; notes generated from merged PRs, or `NOTES_FILE=<path>` (outside the worktree: `dist/` is deleted by the next `dist`) |
| `notary-setup` | Once per Mac. `API_KEY=AuthKey_<id>.p8 API_KEY_ID=<id> API_ISSUER=<issuer>`, or `APPLE_ID=… TEAM_ID=…` in a real terminal |
| `print-version` | The version and where it came from |

The steps `sign`, `notarize`, `staple` and so on can be run alone, and
each runs the ones before it.

## When notarization fails

`notarytool` prints a submission id and **status: Invalid**. `xcrun
notarytool log <id> --keychain-profile <NOTARY_PROFILE>` says why; nearly
always an executable without the Developer ID, the hardened runtime or the
timestamp, which for nested code means `MAC_DIST_SIGN_NESTED` is missing
it.

## What it does not do

- Distribute the app to anyone: see
  [`homebrew-cask`](https://github.com/tikitu/app-tooling/tree/main/patterns/homebrew-cask)
  for a cask in a private tap.
- Sign or notarize anything but an `.app`: an installer package, a disk
  image, or a bare command-line tool (which cannot be stapled).
- Sparkle or any other updater.
