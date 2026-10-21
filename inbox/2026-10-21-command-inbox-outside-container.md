# The command inbox and scratch data trip the "data from other apps" prompt

**Problem.** (TarPit archive viewer, 2026-10-21.) The starter puts the
command inbox in the app's container (`~/Library/Containers/<id>/Data/
Library/Application Support/Commands`), and scratch data in its `tmp`.
`scripts/send-commands.sh` writes and reads there from a terminal, and a
scratch-data copy would have to be written there too. On macOS 15+ a
process without Full Disk Access that touches another app's container
raises "<terminal> would like to access data from other apps" on screen.
That interrupts whoever is using the machine, which is exactly what
`run-background`/`run-scratch` exist to avoid. `docs/gotchas.md` already
notes that reading the container prompts. The agent shell here had no FDA
(`ls ~/Library/Mail` → "Operation not permitted"), so the prompt would have
come up.

**What worked.** Both live outside the container, in
`~/Library/Caches/<App>-scratch/`, and the app reaches them through two
narrow sandbox temporary exceptions (home-relative): `archive/` read-only,
`Commands/` read-write. `UI/Scratch.swift` resolves the real home with
`getpwuid` (under the sandbox `homeDirectory` is the container). TarPit
branch `build-tarpit-archive-viewer-macos`, `Viewer/`, commit 270a1b8.

**Idea.** Make it the starter's default: a `Scratch` location outside the
container for scratch data and the inbox, with the two entitlement
exceptions. Every scratch run then works from an agent shell without FDA.
The cost: the shipped app carries the exceptions too (scratch paths only,
harmless, but App Store review would object; give it a scratch-only
entitlements file if that matters).
