# mac-dist changelog

## Unreleased

- **`make dist` refuses a checkout with changed or untracked files.** It
  only required the tag at `HEAD`, so a modified file, or one never added,
  went into a signed and notarized release named after a commit that does
  not contain it. `check-version` now fails when `git status --porcelain`
  lists anything, and shows what. Git-ignored files do not count, and the
  check runs before the clean, so only what was there beforehand matters.
  `verify-release` (the trial without a tag) does not check. To catch up:
  on a clean checkout, build the release once (`make <MAC_DIST_BUILD>`)
  and run `git status --porcelain`. Anything it lists is build output the
  `.gitignore` is missing, which `make dist` will now refuse: add it to
  `.gitignore`.

## v0.11.0 (2026-11-27)

First version: the starter's `make dist` and `make github-release`, moved
into `mk/mac-dist.mk`, from three apps that had each copied the starter's
`Makefile` and then changed their copies apart. Two of their changes are in
the pattern: `notary-setup` takes an App Store Connect team API key
(`API_KEY`, `API_KEY_ID`, `API_ISSUER`) as well as an Apple Account, and
nested code (a helper tool, a helper app) is signed first by a target the
project names as `MAC_DIST_SIGN_NESTED`, with `$(mac_dist_codesign)`. To
adopt: follow `apply.md`, which replaces a project's own release targets.
