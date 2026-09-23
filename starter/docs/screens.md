# Adding a secondary screen

The template has one window. When the app grows a second screen — a chart, a
review queue, anything opened from the main window — build it this way. On
the Mac a screen is **its own window**, because it is something you keep
open beside the main one; on iOS it is a **sheet**. Nothing about the screen
itself should know which.

## Declare each screen once, as data

A `Screen` enum in the shared package, and **everything needed to offer a
screen hangs off its cases**: `title`, `systemImage`, `help` (the tooltip)
and `shortcut` (⌘-digit on the Mac). Nothing else names a screen or picks its
icon.

| Reads it | For |
|---|---|
| a `ScreenButton` | the toolbar button on every platform: label, icon, tooltip |
| a `ScreenView` | the navigation title, and which view to build |
| the Mac's `ScreenCommands` | the Window-menu item and its shortcut |
| `WindowGroup(for: Screen.self)` (Mac) | the window's identity and restoration; one `WindowGroup` serves every screen |
| `CommandFile` | the `screen` field of a `show` command |

Adding a screen is then: a case, its rows in the property switches, and a
case in `ScreenView`. The compiler finds every switch, and the screen is in
the toolbar, the Window menu, both presentations and the command file with
no further work. Make `Screen` `Codable`, for window restoration.

## Presentation belongs to the platform

The button only ever performs `AppCommand.show(screen)`. What *showing*
means is the model's business, set once per platform at startup:

- **Windows (Mac):** `show` opens a window for the screen, or raises it if
  it is already open — `WindowGroup(for:)` does that for an equal value — and
  records it in the model.
- **Sheets (iOS):** `show` sets `model.screen`, and the root view has one
  `.sheet(item:)` for every screen.

A `dismiss` command closes the innermost thing: the sheet, else the most
recently shown window.

`ScreenView` wraps every screen the same way: a `NavigationStack`, the
title, and — **in a sheet only** — a Done button performing `dismiss`. A
window has a close button; a Done in a window toolbar does not read as a Mac
app. So a screen's own view never adds a Done, a title or a navigation stack.

A screen only one platform has comes in through a closure `ScreenView` is
given by that platform's package, so the shared package never imports
platform code (`rules/platform-conditionals.md`).

## The Mac hands the model its window actions from `Commands`

`openWindow` and `dismissWindow` are SwiftUI environment actions: only a
view or a scene can get one. The model needs them, because a *script* must
be able to open a window (`docs/commands.md`) — and a background-launched
app never runs `onAppear` in its first window (`docs/gotchas.md`), so a view
cannot be relied on to hand them over.

The menu bar is built at launch whether or not the app is active, so the
Mac's `Commands` body runs, and it installs the window actions on the model.
That is what lets `make run-scratch` plus `send-commands.sh` open, raise and
close windows without the app ever being activated.

## Keep the model's list of windows honest

Windows also open and close without a command: the Window menu, ⌘W, the
close button, restoration at launch. So each screen's window reports itself
with `onAppear` and `onDisappear`, to model methods that are idempotent and
keyed by screen.

**Trap:** `dismissWindow` fires the closing window's `onDisappear`
*synchronously*, inside the call. A `dismiss` that removes the last window
from the list *after* calling it removes a second, still-open window as well.
Have it go through the same idempotent "window closed" method, and test that
with fake window actions that call back the same way.
