# Say which patterns an app takes by default

**Problem.** Nothing says which patterns a project should take, so each
update re-lists the same "not imported" patterns and an agent has to ask
again (the v0.1.0 roll-out, 2026-10-18, listed them in every project; the
user settled it on 2026-10-20, hub X8DFT7X).

**Decided (the user, 2026-10-20):**

- every app imports `instruments-profiling`;
- apps with an iOS build import `testflight`; Mac-only apps decline it;
- libraries (e.g. app-utils) import none of the app patterns, and decline
  them in `app-tooling.toml`.

**Idea.** Write this into `patterns/pattern-imports/README.md` (and the
starter's choices) with the next release, so `apply.md` and updates can
say "take these unless declined".
