# homebrew-cask

A Mac app released with
[`mac-dist`](https://github.com/tikitu/app-tooling/tree/main/patterns/mac-dist)
reaches colleagues as a Homebrew cask in a private tap: `brew install
--cask`, and `brew upgrade` for every release after. `make bump-cask` points
the cask at a release once `make github-release` has published it.

The app's releases can stay in a private repository: the cask downloads
them with each colleague's own GitHub CLI login, so no token goes into the
cask, Homebrew's output or anyone's command line.

## What it prevents

- **Every app copying the cask flow from another by hand**, and every copy
  breaking at once when Homebrew changes. When Homebrew 7 began refusing
  casks from untrusted taps, each app's install instructions and its
  `bump-cask` had to be fixed separately; here they change once.
- **A cask that does not match what was published.** `bump-cask` takes the
  checksum from the release's `.sha256`, not from a local build, and has
  Homebrew fetch and check the zip exactly as an install would before it
  commits. If the fetch fails, the cask is put back.
- **A token in the cask.** A plain `url` with an `Authorization` header puts
  the token in the cask, and `brew info --json` prints it.

## The parts

- **In the app** (imported): `scripts/bump-cask.sh` and
  `mk/homebrew-cask.mk`, giving `make bump-cask`. It works on Homebrew's
  own clone of the tap (`brew --repository <user/tap>`), commits there, and
  leaves pushing to the person releasing.
- **In the tap** (copied once, by hand, since a tap is not a project that
  takes patterns): the download strategy
  [`tap/lib/private_github_release.rb`](https://github.com/tikitu/app-tooling/blob/main/patterns/homebrew-cask/tap/lib/private_github_release.rb),
  and a cask like
  [`tap/Casks/myapp.rb`](https://github.com/tikitu/app-tooling/blob/main/patterns/homebrew-cask/tap/Casks/myapp.rb).
  The strategy runs `gh release download`; when `gh` is missing or has no
  access, it says so and points at the releases page instead, and never
  suggests installing or logging in to `gh`.
- **In the docs**: the install steps below, in the app's README, and the
  release steps in its releasing notes.

## Installing, for a colleague

```sh
brew tap <user>/<tap> git@github.com:<owner>/homebrew-<tap>.git
brew trust --cask <user>/<tap>/<cask>
brew install --cask <user>/<tap>/<cask>
```

- **The SSH address**, if their git uses SSH: `brew tap <user>/<tap>` alone
  clones over HTTPS, and every update then asks for a GitHub password.
- **`brew trust`**: Homebrew 7 refuses to load a cask from a third-party
  tap that has not been trusted ("Refusing to load cask … from untrusted
  tap …"). Trusting the one cask is what was tested; `brew trust
  <user>/<tap>` trusts the whole tap. The trust is recorded in
  `~/.homebrew/trust.json` (or `$XDG_CONFIG_HOME/homebrew/trust.json`).
- **`gh`**, logged in with access to the app's repository, if its releases
  are private.

## Releasing, once per Mac

The releaser needs the same tap and trust: `make bump-cask` runs `brew
fetch`, which Homebrew 7 refuses from an untrusted tap just as it refuses
an install. Use the SSH address, so that pushing the tap asks for no
password.

## Releasing, each time

After `make dist` and `make github-release`:

```sh
make bump-cask
git -C "$(brew --repository <user>/<tap>)" push
```

Look at the commit before pushing. Colleagues get the release with `brew
upgrade`.

## What it does not do

- Make or maintain the tap: a private repository named `homebrew-<tap>`,
  holding `Casks/` and `lib/`.
- A formula (for a command-line tool), or a cask for a public tap.
- Push the tap, or open a pull request against it.
