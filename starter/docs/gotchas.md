# Traps

Things that failed in ways that looked like something else. All of them
fail *silently*. They were paid for in earlier apps built on this template,
and the code that avoids them is already here; this is why it looks the way
it does. Read it before "simplifying" anything odd, and add to it.

## `prepareDependencies` fails silently once a dependency has been read

`prepareDependencies` applies only to dependencies not yet accessed, and
SwiftUI's macOS startup reads `defaultDatabase` before `App.init()`.
Bootstrapping there is silently ignored and every `@FetchAll` reads
SQLiteData's blank `:memory:` fallback. Hence `Entry`, an `enum` `@main`
that prepares everything before `StarterApp.main()`. Do not "simplify" it
into `App.init()`.

The same goes for reading a dependency *inside* the preparation closure:
instrumenting the assignment stops it working.

## A preview with no database shows an empty screen

A preview that installs nothing reads SQLiteData's `:memory:` fallback, with
no tables, and shows what looks like "no data yet". Previews call
`bootstrapPreviewDatabase(seed:)`, which runs the real migrator.

## A background-launched window never runs `.task` or `onAppear`

`make run-background` and `make run-scratch` launch with `open -g`. Anything
a scripted run depends on — starting the command inbox, loading data — is
started from `Entry.main()`, not a view.

## A background launch never evaluates `.defaultFocus`

The window never becomes key, so `.defaultFocus` is never evaluated, and
AppKit's initial first responder — the first text field in the view order —
gets every key. Keys posted with `send-keys.swift` type into the field, which
looks like the keyboard handling is broken. `ItemList` therefore takes focus
itself, once, in the `onChange` that runs when rows first arrive; `onChange`
does run in a background window.

## `URL.path()` keeps the percent-encoding

`Application Support` arrives as `Application%20Support`. Always
`path(percentEncoded: false)`. Enforced by `rules/url-path.yml`.

## `open -n` leaves old copies running, and screenshots come from them

Every `make run*` target quits the running copy first (and `pkill`s it if it
will not go). `scripts/window-id.swift` refuses when more than one process
owns a window. If a screenshot looks like a change did not take, check
`pgrep -f build/Starter.app | wc -l` before believing it.

## Only titled windows photograph

An app owns several untitled windows (status-bar and offscreen helpers).
Picking one of those gives a blank white square, which reads as "the app
draws nothing". `window-id.swift` takes only on-screen windows with a title.

## Writing the app's defaults from outside while it runs loses its writes

`defaults write` on a running app's domain: the app picks the change up, and
at the next relaunch both that value and everything the app itself wrote in
the meantime are gone. Nothing reports it; it looks like a setting not
persisting. Set anything a script needs through `configure`. Reading is fine.

## A deleted defaults plist comes back

`rm` on a defaults plist does nothing lasting: cfprefsd holds the domain in
memory and writes it back. `make scratch-reset` uses `defaults delete`, which
goes through cfprefsd.

## `xcodebuild` refuses package macros until they are trusted

The Point-Free libraries are built on Swift macros. `swift build` and
`swift test` use them without asking, but `xcodebuild` fails with "Macro …
must be enabled before it can be used" until each macro package has been
trusted — in Xcode, by clicking "Trust & Enable" in a dialog. A machine where
someone once did that builds fine, which hides the problem until CI or a
fresh checkout on another Mac. So every `xcodebuild` in the Makefile passes
`-skipMacroValidation` (`XCODE_FLAGS`); that is safe to do wholesale because
the dependencies are pinned, and new macro code only arrives through a
reviewed `make update-pins`.

## `log` is shadowed in zsh

`log show …` prints nothing and exits 0 in zsh, where `log` is a builtin.
Always `/usr/bin/log show --predicate 'subsystem == "org.example.starter"'`.

## `swift format` breaks a `#if` between view modifiers, and mangles scripts

It moves a `#if` onto the end of the previous line, which does not compile —
so `make check` after `make fmt`. (Platform `#if`s are banned outright,
`rules/platform-conditionals.md`; this still bites `#if DEBUG`.) And it folds a `#!/usr/bin/env swift`
shebang together with the comments beneath it, so `scripts/` is not
formatted (`SWIFT_FORMAT_PATHS := Packages`).

## Reading the container prompts, once per process

Every `sqlite3 ~/Library/Containers/org.example.starter/…` can raise the
"would like to access data from other apps" dialog, attributed to the
terminal. Grant it Full Disk Access, or batch the queries.
