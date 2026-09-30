# Agent instructions for app-tooling itself

This file is for working *on* this repository. The instructions for an app
made from the starter are in `starter/AGENTS.md`. How a project takes
patterns is in `patterns/pattern-imports/README.md`; how to write one, in
`patterns/README.md`.

* **Readers do not have the author's other projects.** Nothing outside
  `inbox/` may depend on knowing a particular app, person or machine. Use
  `MyApp`, `My iPhone` and the like in examples.

* **Every change a project must act on gets a changelog entry**, under
  `## Unreleased`, in the changed pattern's `CHANGELOG.md` and in the root
  `CHANGELOG.md`. Say what a project that already has the pattern must do,
  not only what changed.

* **A shared file changes here, not in a project's copy.** If a project
  needs something different, make it a parameter.

* **Never add tooling that merges a project's edits to imported files with
  a pattern's changes**, or that makes such a merge easy. Diverging from a
  pattern is a decision (build on the imported file without changing it,
  move the change here, or, last, take the file over as a recorded
  deviation), and it must not become the path of least resistance. Anyone
  can still merge by hand.

* **When a project cannot build on a pattern without editing it, the
  pattern is missing a seam.** Add one (a parameter, a target meant to be
  depended on) rather than letting projects take files over.

* **Pattern documents are read inside other projects** (imported to
  `docs/app-tooling/<pattern>/`): link outside the pattern's directory by
  full GitHub URL only.

* **The starter takes patterns through peru, like any project**, and its
  imported files (`starter/scripts/stamp-git-commit.sh`,
  `starter/mk/app-tooling.mk`, `starter/docs/app-tooling/`) are never
  edited in place. Its `peru.yaml` can only name a commit that already
  exists, so a pattern change reaches the starter in two commits: commit the
  pattern, then, from `starter/`,
  `make app-tooling-update APP_TOOLING_LOCAL=..` and commit that, with any
  change to the starter's own files the update needs.

* **Promote from `inbox/` only once it has been verified in a project**,
  and delete the inbox item in the same commit.

* **Projects may follow a branch.** Do not rewrite history on a pushed
  branch, and do not squash-merge one: projects record its commits.

* Releases are made by the user; `RELEASING.md` has the steps. Do not tag
  or push a release unasked.
