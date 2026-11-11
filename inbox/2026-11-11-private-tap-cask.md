# A cask in a private tap: nothing here, so each app copies it

**Problem.** The starter stops at a GitHub release (`make dist`,
`make github-release`). Several of the author's internal Mac apps then
reach colleagues as a Homebrew cask in a private tap: the cask downloads
the release asset with the colleague's own `gh` login (a download strategy
kept in the tap), a `make bump-cask` sets the cask's `version` and
`sha256` from the published `.sha256`, has `brew fetch` check it, and
commits to Homebrew's clone of the tap. None of that is here, so each app
copied it, its install instructions included, from an older one by hand.
An app made from the starter at v0.8.0 got the copied `bump-cask.sh` and a
two-line install (`brew tap`, `brew install --cask`), and nothing from the
starter itself.

Homebrew 7 then broke every copy at once (2026-11-11, Homebrew 7.0.12):
it refuses to load a cask from a third-party tap the user has not trusted
("Refusing to load cask <user>/<tap>/<cask> from untrusted tap
<user>/<tap>. Run `brew trust --cask …` or `brew trust <user>/<tap>` to
trust it."). Homebrew 6 needed no trust, and one app's packaging notes said
so. Installing fails, and so does `make bump-cask`, whose `brew fetch`
loads the cask the same way. The fix had to be made in each app's README,
packaging and releasing notes, and in the tap's own README, separately.

**What worked.** `brew trust --cask <user>/<tap>/<cask>` once, between
`brew tap` and `brew install --cask`; then the install and `brew fetch`
load the cask. It is recorded in `~/.homebrew/trust.json` (or
`$XDG_CONFIG_HOME/homebrew/trust.json`). Per-cask trust is what was tested;
`brew trust <user>/<tap>` trusts the whole tap. The releaser needs the
same trust, once per Mac, for `make bump-cask`. `external.md` already
gives the same advice for Point-Free's tap.

**Idea.** A `homebrew-cask` pattern for an app distributed through a
private tap: `scripts/bump-cask.sh` and a `make bump-cask` target, with
the tap and cask name as parameters; the `gh` download strategy as a file
for the tap; and the install and release steps as text a project puts in
its README and `docs/releasing.md`, the `brew trust` step included, so the
next change in Homebrew is made once, here. Until then, a project that
already has a cask in a private tap: add the `brew trust --cask` line to
its install instructions and to its releaser's once-per-Mac setup.
