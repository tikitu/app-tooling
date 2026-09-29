# Releasing

Projects refer to app-tooling by release: `app-tooling.toml` in each one
names the tag it was brought into line with, and links go to
`https://github.com/tikitu/app-tooling/tree/<tag>/…`. A project can follow a
branch instead while a pattern is being worked out (`patterns/README.md`),
but that is meant to end in a release: make one whenever a change is ready
to be applied elsewhere, and the projects on its branch then move to it.

## Version numbers

`vMAJOR.MINOR.PATCH`, and while this is `0.x`:

- **minor** (`v0.2.0`) for a new pattern, or any change a project that
  already has a pattern must act on (anything with a catch-up step in a
  pattern's `CHANGELOG.md`);
- **patch** (`v0.1.1`) for changes nobody has to act on: wording, a fix to
  the starter only.

## Steps

1. **Changelogs.** In `CHANGELOG.md` and each `patterns/*/CHANGELOG.md`,
   rename `## Unreleased` to `## vX.Y.Z (YYYY-MM-DD)`. The root one
   summarises and points at the patterns' own entries.
2. **The starter's record.** In `starter/app-tooling.toml`, set `starter`
   and the `release` of every pattern whose last change is in this release
   to `vX.Y.Z`.
3. **Check** that nothing still says unreleased where it should not:
   `grep -rn -i unreleased CHANGELOG.md patterns starter/app-tooling.toml`
   should print nothing (an `Unreleased` heading with no entries under it
   may simply be removed).
4. **Commit** as `Release vX.Y.Z`, then tag and publish:

   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main vX.Y.Z
   gh release create vX.Y.Z --title vX.Y.Z --notes "<the root CHANGELOG entry>"
   ```

5. **Start the next round**: add `## Unreleased` back at the top of
   `CHANGELOG.md` when the next change lands, not before.

A branch that projects follow is merged with a merge commit, not squashed,
so the commits they recorded stay in `main`'s history.

A tag is never moved or reused. A mistake in a release is fixed by the next
one.
