# mac-dist changelog

## v0.11.0 (2026-11-27)

First version: the starter's `make dist` and `make github-release`, moved
into `mk/mac-dist.mk`, from three apps that had each copied the starter's
`Makefile` and then changed their copies apart. Two of their changes are in
the pattern: `notary-setup` takes an App Store Connect team API key
(`API_KEY`, `API_KEY_ID`, `API_ISSUER`) as well as an Apple Account, and
nested code (a helper tool, a helper app) is signed first by a target the
project names as `MAC_DIST_SIGN_NESTED`, with `$(mac_dist_codesign)`. To
adopt: follow `apply.md`, which replaces a project's own release targets.
