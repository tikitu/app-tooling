# scratch-data changelog

## Unreleased

**A sandboxed app cannot pass `--scratch-database`, or any argument, to an
app it launches.** `NSWorkspace.OpenConfiguration.arguments` and
`.environment` are ignored when the launching app is sandboxed, silently,
so a helper or second app launched from a scratch run with a scratch flag
starts on real data. The README has a new section on it. A project that has
the pattern: take the update, and check that the app never launches another
app or helper whose default is real data while on scratch data; if it does,
start the helper's scratch copy from the terminal instead and have the app
only signal it (the README says how).

## v0.3.0 (2026-10-20)

**`quit-running` could quit the real app.** It found the app with
`pgrep -f "$(APP)/Contents/MacOS/"`, which for a relative `APP` (such as
`build/MyApp.app`) also matches the real app running from another checkout
of the project, and then quit it by bundle id, which reaches the real app
from any checkout. It now quits only processes whose command line starts
with this checkout's absolute `$(APP)`, each by its pid, and never uses the
bundle id. `BUNDLE_ID` is no longer a parameter of the fragment.

A project that has the pattern: update it (`make app-tooling-update`).
Nothing else is required. If it worked around this (for instance
`run-scratch scratch-reset: APP := $(CURDIR)/$(APP)` and
`run-scratch scratch-reset: BUNDLE_ID :=` before the include), delete those
lines and the deviation recorded in `app-tooling.toml`. A project with its
own `quit-running` (made from the starter, or copied) has the same hazard:
replace it with the fragment's (`apply.md`), or copy the fragment's version.

## v0.2.0 (2026-10-20)

First version: `mk/scratch-data.mk`, with `make run-scratch` and
`make scratch-reset`, from the starter's targets. `scratch-reset` now
refuses a `SCRATCH_DIR` whose name does not contain `scratch`. A project
with its own copies of these targets (any made from the starter): follow
`apply.md`, delete its `run-scratch`, `scratch-reset` and `quit-running`,
and include the fragment with its parameters.
