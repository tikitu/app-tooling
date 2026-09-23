# Semgrep rules

Run everything here before calling a piece of work finished:

```sh
make semgrep          # semgrep scan --config semgrep --error Packages
```

Inside a git repo Semgrep scans **only tracked files**, so a new file is
invisible to it until it is `git add`ed. Stage before scanning.

The directory is deliberately **not** `.semgrep/`: implicit loading of
`.semgrep/` was deprecated in Semgrep 1.38.0, so the dot bought nothing and
hid documents meant to be read.

## The convention

**Every rule is paired with a document in `docs/`, and its `message` ends with
the path to that document.** A rule that only says *what* is forbidden makes
whoever tripped it guess whether it matters; the document is where the
evidence lives, so they can decide for themselves — including deciding the
rule is wrong for their case.

Each document says: the rule, why it matters, what it cost, what to do
instead, **when a finding is not a bug**, and what would break the rule.

Rules here are for invariants that fail **silently** — the code runs, reports
success, and is wrong. A mistake the compiler or a glance at the screen would
catch does not need one.

## Rules

| File | Document | Invariant |
|---|---|---|
| `erase-on-schema-change.yml` | [docs/erase-on-schema-change.md](docs/erase-on-schema-change.md) | The migrator never erases the database on a schema change |
| `url-path.yml` | [docs/url-path.md](docs/url-path.md) | Filesystem paths come from `path(percentEncoded: false)`, never `path()` |
| `platform-conditionals.yml` | [docs/platform-conditionals.md](docs/platform-conditionals.md) | Platform code is split by package, never by `#if os(…)` |
| `writes-outside-the-model.yml` | [docs/writes-outside-the-model.md](docs/writes-outside-the-model.md) | In the UI target only `AppModel` writes to the database |

## Adding a rule

Validate it in **both** directions before trusting it, ideally against real
history rather than invented examples:

- it flags the code as it was when the bug existed (`git show <sha>~1:<path>`)
- it does not flag the code as it is now

Record the shas — or, where there is no history yet, the reconstructions —
you validated against in the document.
