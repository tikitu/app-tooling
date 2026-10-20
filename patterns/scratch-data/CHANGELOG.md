# scratch-data changelog

## v0.2.0 (2026-10-20)

First version: `mk/scratch-data.mk`, with `make run-scratch` and
`make scratch-reset`, from the starter's targets. `scratch-reset` now
refuses a `SCRATCH_DIR` whose name does not contain `scratch`. A project
with its own copies of these targets (any made from the starter): follow
`apply.md`, delete its `run-scratch`, `scratch-reset` and `quit-running`,
and include the fragment with its parameters.
