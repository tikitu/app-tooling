---
name: derived-data-cleanup
description: Find Xcode DerivedData directories whose source project or git worktree no longer exists, and delete only those, to free disk space without throwing away build caches still in use. Use when asked to clean up DerivedData, free disk space taken by Xcode, or remove build data left behind by deleted worktrees or clones.
---

# Cleaning up orphaned DerivedData

Use `scripts/derived-data-orphans.py` (beside this file). Do not write your
own: an ad-hoc script that guesses wrong deletes caches still in use, and the
next build of that project starts from nothing.

```sh
scripts/derived-data-orphans.py            # report; deletes nothing
scripts/derived-data-orphans.py --delete   # delete what is proven orphaned
```

Run the report first and show the user what it found. Deleting is the
user's decision, even for `orphaned` entries.

## How a directory is traced to its source

`~/Library/Developer/Xcode/DerivedData/<Name>-<28 letters>`: the letters are
an MD5 of the absolute path Xcode opened (an `.xcodeproj`, `.xcworkspace` or
package directory), as given rather than with symlinks resolved, written in
base 26. When Xcode itself opened the project, `info.plist` in the
directory records that path as `WorkspacePath`, and the script recomputes
the letters from it, so the path is proven, not guessed. If a future Xcode
changes the scheme, nothing matches, every directory becomes `unknown` and
nothing is deleted. The `<Name>` prefix is not trustworthy and is not used.

`xcodebuild` on the command line writes no `info.plist`, and nothing else
inside reliably names the path. Such a directory is traced only when a
sibling with an `info.plist` has the same letters (same letters, same path);
otherwise it is `unknown`.

Note that the path is the project's, not the worktree's: a worktree with
several projects or packages has several DerivedData directories.

## What the statuses mean

| Status | Meaning | `--delete` |
|---|---|---|
| `orphaned` | Source path gone, and its nearest surviving ancestor is not in a git work tree: the worktree or clone is gone. Nothing will build into it again unless that exact path is recreated. | deleted |
| `source-missing-in-repo` | Source path gone, but its parent is still in a git work tree: the project moved or was renamed, or the current branch lacks it. A checkout can bring it back. | only if named with `--also NAME` |
| `unknown` | The path could not be proven, or its absence could mean something else: no `info.plist`, a hash mismatch, an unreadable path, a dangling symlink, an unmounted volume (`/Volumes/…`) or a renamed home (`/Users/…`). | never |
| `in-use` | Source exists. May still be stale (see the last-used date), but that is a judgement, not a fact the script can establish. | never |
| `not-a-project` | Shared caches (`ModuleCache.noindex`, `SDKExplicitPrecompiledModules`, …) used by every project, and anything not named like a project's directory. | never |

Each entry is classified again immediately before it is deleted, and skipped
if anything changed. The script only removes plain directories directly
inside the DerivedData directory.

## Rules

- **Offer `source-missing-in-repo` entries one at a time**, with the repo
  and missing path the report shows, and use `--also NAME` only for the ones
  the user agrees to. An old layout of a repo that has since moved its
  project is the common case and usually safe, but the user knows whether
  they still check out old branches.
- **Never delete `unknown`, `in-use` or `not-a-project` entries with this
  skill**, and do not hand-delete them as a workaround. If the user wants
  one gone, they can do it themselves (or in Xcode: Settings → Locations →
  DerivedData).
- **A custom DerivedData location** (Xcode's
  `IDECustomDerivedDataLocation`) makes the script stop; pass `--root` with
  that directory. Per-project `-derivedDataPath` directories are out of
  scope.
- **Xcode can stay open.** Nothing builds into a directory whose source is
  gone.

## Tests

`scripts/test-derived-data-orphans.py` builds a made-up DerivedData
directory and checks every status and every guard on deletion, and checks
the hash against the directories Xcode has made on this Mac. Run it after
changing the script, and after a new Xcode.
