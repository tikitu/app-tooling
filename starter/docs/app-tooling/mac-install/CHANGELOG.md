# mac-install changelog

## Unreleased

First version, from an app whose installed build had always been `1` and
whose Dock kept an old icon after a new one was installed. `make install`
builds with a date-and-time build number, quits a running copy by path,
replaces it with `ditto`, registers it, and restarts it if it was running;
it warns when the build number has not risen. `make
mac-stale-registrations` lists (and with `UNREGISTER=1` unregisters) other
LaunchServices registrations of the bundle id. The README has the order in
which to clear icon caches, ending with the one that needs sudo. Tried on
the starter, installing into a scratch directory. To adopt: follow
`apply.md`, which replaces a project's own `install` target.
