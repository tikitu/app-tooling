# Applying homebrew-cask

Read [`README.md`](README.md) first for what this does and why. Requires
`mac-dist`: `make bump-cask` finds the release by its tag and the zip
`mac-dist` names.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|homebrew-cask`.
- **Copied by hand:** a `scripts/bump-cask.sh` with the repository, the tap
  and the cask written into it, and a `bump-cask` target in the `Makefile`
  that calls it with `$(VERSION)`. The steps below replace both. Compare
  the script with this pattern's first; anything it does that this does
  not, describe to the user before replacing it.
- **Something else doing this job.** A cask in a public tap or in
  homebrew/cask; `brew bump-cask-pr`; a CI job that edits the tap; a
  release script that writes `sha256` into a cask. Describe it to the
  user, and ask, before changing anything.
- **The tap's side:** whether the tap already has
  `lib/private_github_release.rb`, and whether it matches this pattern's
  [`tap/lib/private_github_release.rb`](https://github.com/tikitu/app-tooling/blob/main/patterns/homebrew-cask/tap/lib/private_github_release.rb).
  A difference is for the user to settle; never change the tap unasked.
- **Not adopted:** the app has no cask.

## Parameters

| Parameter | Where to find it |
|---|---|
| `HOMEBREW_CASK_REPO` | the app's GitHub repository, `owner/repo`: `gh repo view --json nameWithOwner -q .nameWithOwner` |
| `HOMEBREW_CASK_TAP` | the tap as `brew tap` names it, `user/tap` (for the repository `owner/homebrew-tap`, it is `owner/tap`) |
| `HOMEBREW_CASK_NAME` | the cask's file name in the tap's `Casks/`, without `.rb` |
| `HOMEBREW_CASK_ASSET` | only if the cask downloads something other than `mac-dist`'s `<Name>-<version>-macos.zip`. Check the cask's `url` |

## Steps

The project must already have `pattern-imports` and `mac-dist`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|homebrew-cask: ./
    app-tooling|homebrew-cask-docs: docs/app-tooling/homebrew-cask/
```

and beside the other rules:

```yaml
rule homebrew-cask:
    export: patterns/homebrew-cask/files
rule homebrew-cask-docs:
    pick: [patterns/homebrew-cask/README.md, patterns/homebrew-cask/apply.md, patterns/homebrew-cask/CHANGELOG.md]
    export: patterns/homebrew-cask
```

A hand-copied `scripts/bump-cask.sh` is in the way: delete it first
(`git rm`), then `uvx peru@1.3.5 sync`.

**2. The `Makefile`.** Delete the project's own `bump-cask` target, and
keep its `.PHONY` entry or not (the pattern declares it). After the
`include mk/mac-dist.mk`:

```make
# `make bump-cask`: the cask in the private tap, at the published release
# (app-tooling: homebrew-cask). docs/app-tooling/homebrew-cask/.
HOMEBREW_CASK_REPO := example/myapp
HOMEBREW_CASK_TAP  := example/internal
HOMEBREW_CASK_NAME := myapp
include mk/homebrew-cask.mk
```

**3. `app-tooling.toml`.**

```toml
[patterns.homebrew-cask]
params = { repo = "example/myapp", tap = "example/internal", cask = "myapp" }
```

**4. The docs.** The app's README says how to install it: the three
commands from this pattern's README, with the tap, the trust and the SSH
address. Its releasing notes add the tap and the trust to the once-per-Mac
setup, and `make bump-cask` and the push after `make github-release`. If
the tap or the team documents these in one place, link that instead of
repeating it.

## Verify

```sh
make -n bump-cask
make bump-cask VERSION=<the version the cask is at now>
```

- `make -n` shows `scripts/bump-cask.sh` with the repository, tap, cask
  and `--asset <Name>-<VERSION>-macos.zip`, matching the cask's `url`.
- The second, for the version already in the cask, downloads the
  published checksum, finds nothing to change and prints `✓ the cask is
  already at <version>`. `✗ no … .sha256` means the repository or asset
  name is wrong; `✗ no clone of <tap>` means the tap name is, or the tap
  is not tapped on this Mac; `✗ no Casks/<name>.rb` (said after pulling
  the tap) means the cask name is, or the cask is not merged into the tap
  yet.
- `brew fetch --force --cask <user>/<tap>/<cask>` downloads with `gh` and
  checks the checksum, as the next bump will. A refusal naming an
  untrusted tap means the trust step is missing on this Mac.
