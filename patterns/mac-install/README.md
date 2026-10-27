# mac-install

`make install` puts the Mac app in `/Applications` with a build number that
rises every time, quits and restarts a running copy, and registers it with
LaunchServices. And when the Dock still shows the old icon after all that,
this says what to try, in order, instead of hunting.

## The problem

An app installed by hand (`cp -R` or `ditto` into `/Applications`) usually
keeps whatever `CFBundleVersion` the project started with, often `1`, for
every install. macOS caches per bundle, and a bundle that changes without
its version changing is the case those caches handle worst. After a new
icon, Finder, Spotlight and `NSRunningApplication.icon` showed it, and the
Dock kept drawing the old one.

Copying over a running app has its own trouble: the old process keeps
running from deleted files until someone quits it, and nobody notices that
the "new" build they are looking at is the old one.

## What it does

`make install` (`mk/mac-install.mk`) builds with
`$(MAC_INSTALL_BUILD_NUMBER)` as the build number, the date and time to the
second, then runs `scripts/mac-install.sh`, which:

1. checks the built app's signature, and **warns when its build number is
   not above the installed copy's**: an Xcode build that ignored the number,
   or a mix of numbering schemes;
2. quits the installed copy if it is running, found by its executable's
   absolute path (never by bundle id, which would also reach builds from
   checkouts), and gives up rather than killing it if it does not quit;
3. replaces it with `ditto` and checks the signature of what arrived;
4. runs `lsregister -f` on it, so LaunchServices reads the new bundle now;
5. starts it again, in the background, only if it was running.

`make mac-stale-registrations` (`scripts/mac-stale-registrations.sh`) lists
every other LaunchServices registration of the bundle id, with its build
number, and marks those whose bundle is gone. Every build that was ever
launched is registered: DerivedData, `build/`, worktrees, `/tmp`. With
`UNREGISTER=1` it runs `lsregister -u` on each; nothing on disk is deleted,
and a build that is launched again registers again.

## When the old icon stays

Try these in order, and stop when the Dock is right. Each is more
disruptive than the one before.

1. **A rising build number.** `make install` gives one; if it warned that
   the number had not risen, fix that first.
2. **Stale registrations.** `make mac-stale-registrations`, then with
   `UNREGISTER=1`, then `killall Dock`.
3. **The per-user caches**, which live under `getconf DARWIN_USER_CACHE_DIR`
   (in `/var/folders`), not `~/Library/Caches`:

   ```sh
   C="$(getconf DARWIN_USER_CACHE_DIR)"
   rm -rf "${C:?}com.apple.dock.iconcache" "${C:?}com.apple.iconservices"
   killall Dock
   ```

   Either may be absent; that is not a failure.
4. **The system icon store.** This was the only thing that fixed it the
   first time it was seen, after all of the above had failed:

   ```sh
   sudo rm -rf /Library/Caches/com.apple.iconservices.store
   killall iconservicesagent Dock
   ```

   It needs `sudo`, so it is the user's to run. **An agent stops here and
   asks**, with the commands, rather than looking for another way round.
   It is harmless (the store is rebuilt), but every app's icon redraws
   once.

A restart of the Dock on its own does nothing for this, and is not worth
trying first.

## Why this shape

- **The date, not the commit count.** `git-commit-stamp`'s `<count>.<dirty>`
  stays the same for every build of an uncommitted change, which is exactly
  when someone iterates on an icon. The date rises on every install. It is a
  local build number only: TestFlight has its own (`testflight`).
- **A warning, not a refusal, when the number has not risen.** Reinstalling
  the same build is legitimate (after deleting the installed copy's data,
  say). The warning says what it may cost.
- **Quit, never kill.** The installed copy is the real app, on real data,
  possibly in the middle of a save or a sync.

## What it asks of a project

- A target that builds the Mac app with `$(MAC_INSTALL_BUILD_NUMBER)` as its
  `CFBundleVersion`: `CURRENT_PROJECT_VERSION=$(MAC_INSTALL_BUILD_NUMBER)` on
  the `xcodebuild` command line, or for a `build.sh` that writes the
  `Info.plist` itself, the number passed in the environment.
- The app's name in `/Applications` is the built bundle's name.

It does not make an iOS install (`devicectl`), uninstall, or notarize: a
local install of a locally signed build is all it does. If the project
stamps `CFBundleVersion` some other way after the build (`git-commit-stamp`'s
`--bundle-version`, on the Mac), that stamp wins, and the warning in step 1
will say when it stops rising.

## Files

Imported by peru, never edited in a project:

| File | Imported as |
|---|---|
| `files/mk/mac-install.mk` | `mk/mac-install.mk` |
| `files/scripts/mac-install.sh` | `scripts/mac-install.sh` |
| `files/scripts/mac-stale-registrations.sh` | `scripts/mac-stale-registrations.sh` |

Requires the `pattern-imports` pattern. `apply.md` has the steps;
`CHANGELOG.md` what changed between releases.
