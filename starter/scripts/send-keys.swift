#!/usr/bin/env swift
// Presses keys in a running app without activating it or moving the pointer.
//
//   scripts/send-keys.swift <pid> <key>...     e.g.  down down return x
//
// Events go to the process, not the focused app, so the laptop stays usable
// while the app is driven. Names: up down left right return escape space
// delete tab, or a single character, optionally prefixed with modifiers:
// shift+down, cmd+a. See plans/keyboard.md.
import CoreGraphics
import Foundation

let named: [String: CGKeyCode] = [
    "up": 126, "down": 125, "left": 123, "right": 124, "return": 36, "escape": 53,
    "space": 49, "delete": 51, "tab": 48,
]
let letters: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
    "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
    "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
]

let arguments = CommandLine.arguments.dropFirst()
guard let pid = arguments.first.flatMap({ pid_t($0) }), arguments.count > 1 else {
    FileHandle.standardError.write("usage: send-keys.swift <pid> <key>...\n".data(using: .utf8)!)
    exit(2)
}
let source = CGEventSource(stateID: .privateState)
let modifierFlags: [String: CGEventFlags] = [
    "shift": .maskShift, "cmd": .maskCommand, "opt": .maskAlternate, "ctrl": .maskControl,
]
for argument in arguments.dropFirst() {
    var parts = argument.split(separator: "+").map(String.init)
    let key = parts.removeLast()
    var flags: CGEventFlags = []
    for part in parts {
        guard let flag = modifierFlags[part] else {
            FileHandle.standardError.write("unknown modifier '\(part)'\n".data(using: .utf8)!)
            exit(2)
        }
        flags.insert(flag)
    }
    guard let code = named[key] ?? (key.count == 1 ? letters[Character(key)] : nil) else {
        FileHandle.standardError.write("unknown key '\(key)'\n".data(using: .utf8)!)
        exit(2)
    }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.postToPid(pid)
        usleep(30_000)
    }
    usleep(120_000)
}
