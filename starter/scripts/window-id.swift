#!/usr/bin/env swift
// Prints the window id of a running app's main window, for
// `screencapture -l <id>`, which photographs a window without activating it.
//
//   scripts/window-id.swift "Starter App"
//
// Exits non-zero, with a message, if there is no such window — or more than
// one process owning one, which means an old copy is still running and the
// screenshot could come from it (plans/gotchas.md).
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Starter App"
let windows =
    CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
let mine = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner
        && ($0[kCGWindowLayer as String] as? Int) == 0
        && ($0[kCGWindowIsOnscreen as String] as? Bool) == true
        // The real window has a title; the app's untitled ones are status
        // bar and offscreen helpers, and photograph as blank squares.
        && !(($0[kCGWindowName as String] as? String) ?? "").isEmpty
}
let owners = Set(mine.compactMap { $0[kCGWindowOwnerPID as String] as? Int })
guard owners.count == 1, let window = mine.first,
    let id = window[kCGWindowNumber as String] as? Int
else {
    FileHandle.standardError.write(
        "✗ \(owners.count) processes named '\(owner)' have a window; want exactly 1\n".data(
            using: .utf8)!)
    exit(1)
}
print(id)
