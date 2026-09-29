# Agent instructions for app-tooling itself

This file is for working *on* this repository. The instructions for an app
made from the starter are in `starter/AGENTS.md`; the instructions for
applying a pattern to a project are in `patterns/README.md`.

* **Readers do not have the author's other projects.** Nothing outside
  `inbox/` may depend on knowing a particular app, person or machine. Use
  `MyApp`, `My iPhone` and the like in examples.

* **Every change a project must act on gets a changelog entry**, under
  `## Unreleased`, in the changed pattern's `CHANGELOG.md` and in the root
  `CHANGELOG.md`. Say what a project that already has the pattern must do,
  not only what changed.

* **A shared file changes here, not in a project's copy.** If a project
  needs something different, make it a parameter.

* **The starter and the patterns must agree.** Where the starter carries a
  pattern, change both in the same commit, and keep
  `starter/app-tooling.toml` listing what it carries.

* **Promote from `inbox/` only once it has been verified in a project**,
  and delete the inbox item in the same commit.

* **Projects may follow a branch** (`patterns/README.md`). Do not rewrite
  history on a pushed branch, and do not squash-merge one: projects record
  its commits.

* Releases are made by the user; `RELEASING.md` has the steps. Do not tag
  or push a release unasked.
