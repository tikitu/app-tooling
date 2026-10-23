# A sandboxed app's scratch data is still in its container

**Problem.** (Left from hub ticket 4E4H6YB, TarPit archive viewer,
2026-10-21; the command-inbox half became the `command-inbox` pattern on
2026-10-22.) `scratch-data` puts a sandboxed app's scratch database in the
container's `tmp`, so `make scratch-reset` (`rm -rf` there) and any target
that copies data into a scratch run touch another app's container from a
terminal. Without Full Disk Access that raises "would like to access data
from other apps" on the screen of whoever is using the machine. The starter
has the same `rm -rf` in its own `scratch-reset`.

**What worked.** TarPit keeps its scratch archive copy in
`~/Library/Caches/TarPitArchive-scratch/archive`, opened read-only by a
home-relative sandbox temporary exception; the app resolves the real home
with `getpwuid` (under the sandbox `homeDirectory` is the container). TarPit
branch `build-tarpit-archive-viewer-macos`, `Viewer/`, commit 270a1b8.

**Idea.** `scratch-data` for a sandboxed app: the scratch directory at
`~/Library/Caches/<App>-scratch/` beside `command-inbox`'s `Commands/`, given
to the app as a launch argument (`SCRATCH_ARGS`) rather than worked out from
`URL.temporaryDirectory`, with a read-write exception for it. The defaults
suite stays in the container; `defaults delete` goes through cfprefsd and
does not prompt.
