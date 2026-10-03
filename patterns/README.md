# Patterns

The starter is for new apps. Patterns are for apps that already exist: each
is one convention, packaged so that an agent can bring an existing project
into line with it, and bring it up to date later.

A pattern can be anything that has proved itself in one app and would help
another: a script, a Makefile fragment, a build phase, an ast-grep rule, a
change to how a project is laid out. It may carry files, or only
instructions.

This page is for writing and changing patterns. How a project takes them,
records them and updates them is the first pattern,
[`pattern-imports`](pattern-imports/README.md), which every project takes
first.

## How projects get them

Projects import patterns with [peru](https://github.com/buildinspace/peru),
from `https://github.com/tikitu/app-tooling`, pinned at one commit for all
of a project's patterns. A project follows a release tag, or a branch while
a pattern is being worked out; it records the commit either way, so a moved
tag or branch changes nothing until the project updates, and then shows as
a diff. A project can read from a local checkout instead of GitHub.
[`pattern-imports/README.md`](pattern-imports/README.md) has the details.

Because a project is at one commit for everything, patterns are always used
with the versions of each other they were written beside. That is why there
are no per-pattern versions, and no need to resolve them.

## What a pattern is made of

```
patterns/<name>/
  README.md      what it does, why it is preferred, what it costs
  apply.md       for an agent: detect, parameters, steps, verify
  CHANGELOG.md   what changed, and what a project must do to catch up
  files/         imported into the project root as they are laid out
```

A project imports `files/` at its root, and the three documents into
`docs/app-tooling/<name>/`. So the documents are read *inside other
projects*: link to anything outside the pattern's own directory by its full
`https://github.com/tikitu/app-tooling/…` URL, never by a relative path.

**`README.md`** is for the person deciding whether to adopt it. Say what
problem it solves, in terms of the failure it prevents; what it asks of a
project (tools, settings, a build phase); and what it does *not* do. Name
the patterns it requires, if any; "requires" means "take that one too",
nothing more.

**`apply.md`** is for the agent doing the work, in a project that was not
built from the starter and may already have part of this, or something else
doing the same job. It has four sections, always in this order:

1. **Detect.** How to tell whether the project already has the pattern, or
   something else doing the same job. Name the files, targets and settings
   to look for. That second part is the important one: it is where a
   project that solved the problem its own way is recognised, rather than
   given a second solution beside the first.
2. **Parameters.** What differs between projects (names, paths, bundle
   ids), and where in a project to find each one.
3. **Steps.** The first step is always the pattern's two rules and imports
   for `peru.yaml`, given as text to add. After that, what to change. Where
   a step changes a file the project owns (its `Makefile`, `project.yml`,
   `AGENTS.md`), give the text to add and say where it goes.
4. **Verify.** Commands that show it worked, and what their output should
   be. A command that prints nothing and exits 0 proves nothing; say what to
   check instead.

**`CHANGELOG.md`** lists changes newest first, under the release that
shipped them, with `## Unreleased` at the top while work is in progress.
Each entry says what a project that already has the pattern must do to
catch up ("add `--flag` to the build phase", "run `make x` once"). A
project's update prints exactly the entries it added, as its to-do list,
so an entry that only says "improved" is not enough. Changes to `files/`
alone arrive with the update and need no step; say so if it matters.

**`files/`** is laid out as it goes into the project: `files/scripts/x.sh`
becomes `scripts/x.sh`. Two patterns must not import the same path.

## Seams: shared files are never edited in a project

The difference between an update that is easy and one that is a merge is
whether the shared part has a file to itself. So:

- **Shared logic goes in a file the project does not edit**: a script, a
  Makefile fragment to `include`, a rule file. Anything project-specific
  comes in through arguments, environment or make variables. An update
  replaces it whole, and refuses to run while it has been edited.
- **Each such file names its pattern in its header**, and says it is
  imported, so that someone who finds it in a project knows not to edit it
  there and where to go instead.
- **What has to go in a project's own files is kept small** (a build phase
  that calls the script, an `include`) and is given in `apply.md` as text
  to add.

If a project needs a change to a shared file, that is a change to the
pattern: make it here, with a parameter if it is really project-specific.
Better still, where it fits, the project builds on the file without
changing it (its own target around an imported one, say), which a pattern
makes possible by having seams to build on: parameters, targets meant to be
depended on, scripts that do one thing. Taking the file over, as a recorded
deviation, is the last resort, since it gives up every later improvement.
There is no tooling for merging a project's edits with a pattern's, and
there will not be: it would make diverging the easy path
([`pattern-imports`](pattern-imports/README.md#local-changes-to-imported-files)).

## Checking a set of projects

The list of projects is private to whoever keeps them, so it does not live
here. Keep it in a git-ignored `fleet.local.toml` at the root of this
repository:

```toml
projects = ["~/code/MyApp", "~/code/OtherApp"]
```

An agent asked to check them reads, for each project, `peru.yaml` (the
`reup:` it follows and the `rev:` it is at) and `app-tooling.toml`, and
reports which patterns it has, which it lacks or has declined, and how far
its `rev:` is behind its `reup:` (`git log --oneline <rev>..<reup> --
patterns/`, in this repository). It flags a project following a branch that
has since been released or deleted. It changes nothing without being asked.

## Where new patterns come from

Mostly from other projects: something worked there, and would help here.
Those start in [`inbox/`](../inbox/README.md) and are made into patterns
from there.

A pattern is ready when:

- it has been applied to at least one project and verified there;
- nothing in it names a particular app, person or machine, except as an
  example;
- every file in `files/` names its pattern in its header;
- its documents link outside their directory only by full URL;
- its `CHANGELOG.md` has an entry.

If the starter should carry it too, add it to `starter/peru.yaml`;
[`AGENTS.md`](../AGENTS.md) has the order of commits that needs.

## The patterns

| Pattern | What it does |
|---|---|
| [`pattern-imports`](pattern-imports/README.md) | How a project takes patterns: `peru.yaml`, `app-tooling.toml`, `make app-tooling-update` and `app-tooling-check`. Every project takes it first |
| [`git-commit-stamp`](git-commit-stamp/README.md) | Every build records the commit it came from; `make ios-device-which` says which commit is on the phone |
| [`testflight`](testflight/README.md) | `make testflight-upload` archives a clean commit and uploads it to TestFlight; `make testflight-validate` checks without uploading |
| [`ios-simulators`](ios-simulators/README.md) | Simulators the project owns, on the newest iOS and the phone's; `make ios-sims` after an Xcode update. *Draft* |
| [`privileged-helper`](privileged-helper/README.md) | A Mac app runs one command as root without a password each time: a launchd daemon in the bundle, allowed once in System Settings, with Touch ID before the risky direction. Documents only |
