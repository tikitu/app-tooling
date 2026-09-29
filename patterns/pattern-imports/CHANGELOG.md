# pattern-imports changelog

## Unreleased

First version: `peru.yaml` pins app-tooling at one commit and imports each
pattern's files and docs; `mk/app-tooling.mk` provides `app-tooling-update`
and `app-tooling-check`. Tried on a scratch clone of an existing iOS app,
including a tag moved upstream, a local edit to an imported file, a fresh
clone, and reading unpushed commits from a local checkout.
