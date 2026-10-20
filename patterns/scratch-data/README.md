# scratch-data

The Mac app can run on data that does not matter, so that an agent can
launch it, drive it and look at it without ever touching the real database.
`make run-scratch` starts it that way, in the background; `make
scratch-reset` throws the scratch data away.

## The problem

An agent checking a change has to run the app, and the app opens the real
database. Whatever the check does (adds rows, runs a migration, deletes
something to see the empty state) happens to real data. If the app syncs,
it happens to every device. And `open` brings an already running copy to
the front, on whatever data that copy has, so even "launch a fresh build"
is not what it looks like.

## What it does

The app takes a launch argument, **`--scratch-database`**. With it, the app
opens a database in a directory of its own (conventionally
`<App>-scratch/` under the app's temporary directory), uses a user defaults
suite of its own (conventionally `<bundle id>.scratch`), and **never
syncs**. Without it, nothing changes. The app does this; the pattern says
what it must do and supplies the make targets around it.

`mk/scratch-data.mk` gives:

- **`make run-scratch`**: builds, quits the copy of the app at `$(APP)` if
  it is running, and launches it with `--scratch-database`, behind whatever
  has focus (`open -g`), so it works while someone uses the machine. It
  quits only processes started from this checkout's `$(APP)`, by absolute
  path, each by its pid, never by bundle id: the real app, built from
  another checkout of the same project, has the same name and bundle id.
- **`make scratch-reset`**: quits it and deletes the scratch directory and
  the scratch defaults. It refuses a directory whose name does not contain
  `scratch`, so an empty or mistyped variable cannot become `rm -rf` of the
  real data.
- **`quit-running`**, the macro both use, for the project's own `run`
  targets.

`make run` stays the project's, and is for a person: real data, in front.

## What it asks of a project

- A Mac app built by `make` into a known bundle (`$(APP)`).
- The app code for `--scratch-database` (the steps in `apply.md`). It is a
  few lines where the database and the defaults are made, and one condition
  where sync starts.
- `AGENTS.md` telling agents to use `make run-scratch`, never `make run`.

## What it does not do

- **No iOS.** A simulator's whole container is disposable already, so the
  simulator needs no flag, provided the simulator build cannot sync (see
  [`sync-configuration`](https://github.com/tikitu/app-tooling/tree/main/patterns/sync-configuration)).
  A phone is real data, always.
- **No seed data.** The scratch database starts empty. A project that wants
  a copy of real data in it writes that target itself, copying from a
  backup, never the live file.
- **It is not the guarantee against syncing.** A scratch run does not start
  sync, but it is the same binary as `make run`. For an app that syncs, the
  guarantee is that agents' builds are not entitled to sync at all:
  `sync-configuration`.
