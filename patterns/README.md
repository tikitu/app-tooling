# Patterns

The starter is for new apps. Patterns are for apps that already exist: each
is one convention, packaged so that an agent can bring an existing project
into line with it, and bring it up to date later.

A pattern can be anything that has proved itself in one app and would help
another: a script, a Makefile target, a build phase, an ast-grep rule, a
change to how a project is laid out. It may carry files, or only
instructions.

## Referring to app-tooling from elsewhere

Everything outside this repository refers to it as
**`https://github.com/tikitu/app-tooling`, at a release tag**
(`v0.1.0`), never at `main`, and never by a path on someone's machine:

    https://github.com/tikitu/app-tooling/tree/v0.1.0/patterns/git-commit-stamp

A tag says exactly which text a project was brought into line with, and it
stays true when `main` moves on. What a release is, and how to make one, is
in [`RELEASING.md`](../RELEASING.md); what changed in each is in
[`CHANGELOG.md`](../CHANGELOG.md).

## What a pattern is made of

```
patterns/<name>/
  README.md      what it does, why it is preferred, what it costs
  apply.md       for an agent: detect, parameters, steps, verify
  CHANGELOG.md   what changed, under the release it shipped in
  files/         files copied into a project as they are (optional)
```

**`README.md`** is for the person deciding whether to adopt it. Say what
problem it solves, in terms of the failure it prevents; what it asks of a
project (tools, settings, a build phase); and what it does *not* do.
Name the patterns it requires, if any.

**`apply.md`** is for the agent doing the work, in a project that was not
built from the starter and may already have part of this, or an older
version of it. It has four sections, always in this order:

1. **Detect.** How to tell whether the project already has the pattern, an
   earlier release of it, or something else doing the same job. Name the
   files, targets and settings to look for. What counts as "something else
   doing the same job" is the important part: that is where a project that
   solved the problem its own way is recognised, rather than given a second
   solution beside the first.
2. **Parameters.** What differs between projects (names, paths, bundle
   ids), and where in a project to find each one.
3. **Steps.** What to change. Where a step changes a file the project owns
   (its `Makefile`, `project.yml`, `AGENTS.md`), give the text to add and
   say where it goes.
4. **Verify.** Commands that show it worked, and what their output should
   be. A command that prints nothing and exits 0 proves nothing; say what to
   check instead.

**`CHANGELOG.md`** lists changes under the release that shipped them, newest
first, with an `Unreleased` section at the top while work is in progress.
Each entry says what a project that already has the pattern must do to catch
up ("copy `scripts/x.sh` again", "add `--flag` to the build phase"). This is
what an update is made from, so an entry that only says "improved" is not
enough.

**`files/`** is laid out as it goes into the project: `files/scripts/x.sh`
becomes `scripts/x.sh`.

## Seams: shared files are copied whole

The difference between an update that is easy and one that is a merge is
whether the shared part has a file to itself. So:

- **Shared logic goes in a file the project does not edit**: a script, a
  Makefile fragment to `include`, a rule file. Anything project-specific
  comes in through arguments, environment or make variables. Updating is
  then copying the file again and reading the diff.
- **Each such file names its pattern in its header**, so that someone who
  finds it in a project can find where it came from.
- **What has to go in a project's own files is kept small** (a build phase
  that calls the script, a target that calls it) and is given in
  `apply.md` as text to add.

If a project needs a change to a shared file, that is a change to the
pattern: make it here, with a parameter if it is really project-specific,
and not in the copy.

## The record in each project

Every project that takes patterns has an `app-tooling.toml` at its root. It
is what makes "which of these projects are behind?" answerable:

```toml
# Conventions this project takes from app-tooling. Each pattern's apply.md,
# at the release named here, says how it was applied and how to update it.
source = "https://github.com/tikitu/app-tooling"

[patterns.git-commit-stamp]
release = "v0.1.0"
# What was filled in for the pattern's parameters, when it is not obvious.
params = { ios_target = "MyApp", device = "My iPhone" }
# Where this project departs from the pattern on purpose, and why.
deviations = ["Mac app keeps its date-based CFBundleVersion"]

[declined.ast-grep-rules]
release = "v0.1.0"
reason = "keeps its Semgrep rules until they are ported"
```

- **`release`** is the tag the pattern was applied or last updated from.
  While trying out a pattern that is not yet released, write the commit
  instead (`commit = "e153fb6"`) and replace it with the release once there
  is one.
- **`deviations`** and **`[declined.*]`** matter as much as what was
  adopted. Without them, the next agent to bring the project up to date will
  "fix" what was chosen on purpose. A pattern is declined *at* a release
  because it may change enough later to be worth another look.

A project made from the starter has this file from the start, listing what
the starter already carries.

## Applying a pattern (for an agent)

1. Read the project's `app-tooling.toml`, if it has one. If the pattern is
   declined there, stop and say so.
2. Read the pattern's `README.md` and `apply.md` **at the release you are
   applying** (the latest, unless told otherwise).
3. Work through **Detect**. If the project already solves this problem its
   own way, stop and describe both to the user before replacing anything:
   the project's way may be better, and then it belongs here instead.
4. Fill in the **Parameters**, then do the **Steps**.
5. Run **Verify**, and report what it showed.
6. Add or update the pattern's entry in `app-tooling.toml`.
7. Commit in the project, naming the pattern and the release.

To **update** a pattern a project already has: read its `CHANGELOG.md` for
every release after the one recorded, do what each entry says, verify, and
update the recorded release.

## Checking a set of projects

The list of projects is private to whoever keeps them, so it does not live
here. Keep it in a git-ignored `fleet.local.toml` at the root of this
repository:

```toml
projects = ["~/code/MyApp", "~/code/OtherApp"]
```

An agent asked to check them reads each project's `app-tooling.toml`,
compares it with each pattern's `CHANGELOG.md`, and reports, per project,
which patterns are missing, which are behind and by which releases, and
which are declined. It changes nothing without being asked.

## Where new patterns come from

Mostly from other projects: something worked there, and would help here.
Those start in [`inbox/`](../inbox/README.md) and are made into patterns
from there.

A pattern is ready when:

- it has been applied to at least one project and verified there;
- nothing in it names a particular app, person or machine, except as an
  example;
- every file in `files/` names its pattern in its header;
- its `CHANGELOG.md` has an entry.

If the starter should carry it too, change the starter in the same commit,
and list the pattern in `starter/app-tooling.toml`.

## The patterns

| Pattern | What it does |
|---|---|
| [`git-commit-stamp`](git-commit-stamp/README.md) | Every build records the commit it came from; `make ios-device-which` says which commit is on the phone |
