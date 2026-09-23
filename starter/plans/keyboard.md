# The keyboard: working through a list

A Mac window for working through volume has to be usable without the mouse.
The item list is the worked example; follow the same shape for any list the
app grows.

## What is standard

- **Explicit selection, on the model.** `AppModel.selection` is a `Set`, not
  view `@State`, so a script and the menu bar can read and act on it. A
  `Set`, because shift- and ⌘-click multi-select are what a Mac list does.
- **Focus and the first row on open.** The list takes focus and its first
  row is selected as soon as rows arrive. When rows leave (deleted, or hidden
  by Show Done), the selection moves to the nearest row that is left, else
  the first (`SelectionAfter.repaired`).
- **Arrows** come free with a focused `Table` / `List`.
- **Return (or double-click) is the primary action**: here, toggle done.
- **⌫ deletes**, because that is how a Mac list removes a row. It arrives as
  `onDeleteCommand`, never as a key press.
- **The context menu acts on the selection**, one menu for the whole list.
- **The menu bar has every action too**, with shortcuts, acting on the
  model's selection.

## Actions are reached with →

**→ opens the actions beside the selection**, as it opens a submenu: ↑↓
move, Return performs, ← or Esc closes. `ActionMenu` is a list in a popover,
because SwiftUI cannot open a real `NSMenu` from a key.

Single-letter shortcuts were tried instead, in an earlier app, and dropped:
they are hard to remember and do not generalise. The → menu says what there
is, so there is nothing to remember.

## Acting moves on

After an action, the selection moves to the next row
(`AppModel.actOnSelection`, `SelectionAfter.successor`), so working through
a list is → ↓ Return, → ↓ Return. An action that you take *before* deciding
about a row — previewing it, say — is the exception, and should leave the
selection where it is.

## Verifying without focus

`make run-scratch`, then `scripts/send-keys.swift <pid> …` and
`make screenshot`. Two limits: a menu shortcut posted to a background
process is not delivered (the keys fall through to the list), and a
background window draws its selection grey rather than accent-coloured,
which is the inactive state, not a bug.
