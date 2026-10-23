#!/usr/bin/env swift  // Prints the window id of a running app's main window, for
// `screencapture -l <id>`, which photographs a window without activating it.
//
//   scripts/window-id.swift --pid 4242       # that process's window
//   scripts/window-id.swift "Starter App"    # any process of that name
//
// `make screenshot` passes the pid of this checkout's build: by name, a copy
// built in another worktree or checkout has the same name, and its window
// could be photographed instead.
//
// Exits non-zero, with a message, if there is no such window — or more than
// one process owning one, which means an old copy is still running and the
// screenshot could come from it (docs/gotchas.md).
import CoreGraphics
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let pid: Int? = arguments.first == "--pid" ? arguments.dropFirst().first.flatMap { Int($0) } : nil
if arguments.first == "--pid" && pid == nil {
    FileHandle.standardError.write("✗ --pid needs a process id\n".data(using: .utf8)!)
    exit(2)
}
let owner = arguments.first ?? "Starter App"
let windows =
    CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
let mine = windows.filter { window in
    let isOwner =
        if let pid { (window[kCGWindowOwnerPID as String] as? Int) == pid } else {
            (window[kCGWindowOwnerName as String] as? String) == owner
        }
    return isOwner && (window[kCGWindowLayer as String] as? Int) == 0
        && (window[kCGWindowIsOnscreen as String] as? Bool) == true
        // The real window has a title; the app's untitled ones are status
        // bar and offscreen helpers, and photograph as blank squares.
        && !((window[kCGWindowName as String] as? String) ?? "").isEmpty
}
let owners = Set(mine.compactMap { $0[kCGWindowOwnerPID as String] as? Int })
let what = pid.map { "process \($0)" } ?? "processes named '\(owner)'"
guard owners.count == 1, let window = mine.first, let id = window[kCGWindowNumber as String] as? Int
else {
    FileHandle.standardError.write(
        "✗ \(what): \(owners.count) own a titled on-screen window; want exactly 1\n".data(
            using: .utf8)!)
    exit(1)
}
print(id)
