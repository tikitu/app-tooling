# homebrew-cask changelog

## Unreleased

First version, from the inbox item "A cask in a private tap": three apps
had each copied `bump-cask.sh` and their install instructions from one
another, and Homebrew 7's refusal of untrusted taps broke every copy at
once. `make bump-cask` sets the cask's `version` and `sha256` from the
published `.sha256`, has `brew fetch` check it, and commits in Homebrew's
clone of the tap, with the repository, tap, cask and asset as parameters.
The README has the install steps (tap over SSH, `brew trust --cask`,
install) and the release steps; `tap/` has the `gh` download strategy and
an example cask, for the tap. To adopt: follow `apply.md`, which replaces
a hand-copied `bump-cask.sh`.
