# Practices

How a team runs a project — where plans live, how commits are made, who
merges — differs from team to team, and none of it is needed to build the
app. So the template keeps it out of the core and offers it here, as
practices to opt into when the app is created:

```sh
scripts/new-app.sh --list                                   # what there is
scripts/new-app.sh MyApp --with markdown-tracking,commit-hygiene
scripts/new-app.sh MyApp --with all
scripts/new-app.sh MyApp --with none
```

Each chosen practice adds its section to `AGENTS.md` and copies in any files
it brings. This directory is deleted afterwards; to add a practice later,
copy its section and files by hand from a fresh copy of the template.

## The practices, and why you might want them

**`markdown-tracking`** — `PLAN.md` as the index to the docs, `PROGRESS.md`
as a running log, `PROBLEMS.md` for open questions and the reasoning behind
decisions. The point is that an agent starting cold is up to speed after two
files, with no access to anything outside the repo. They go together; the
usual reason to leave them out is an issue tracker that already does this
job.

**`docs-in-step`** — docs change in the same commit as the behaviour they
describe. Agents trust documents completely, so a stale one does more damage
than a missing one.

**`commit-to-main`** — no feature branches; a provisional change gets its
own commit so it can be dropped. Suits one person with no review process.
Leave it out wherever branches and review are the norm.

**`commit-hygiene`** — messages say why and what was verified, and nothing
that does not compile is committed. Makes history useful to a later agent
reconstructing why something is the way it is.

**`no-self-merge`** — an agent may open pull requests but never merge them,
so a human always sees the change land.

## Adding a practice

A directory here holding `summary` (one line, shown by `--list`),
`agents.md` (its section of `AGENTS.md`), and optionally `files/` (copied to
the repo root as they are). Keep practices to how the project is *run*.
Anything the app needs to build, run or be checked belongs in the core.
