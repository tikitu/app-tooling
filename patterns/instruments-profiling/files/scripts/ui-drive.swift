// ui-drive.swift — drive a Mac app's UI from the command line, for profiling
// scenarios with no one at the keyboard.
//
// Imported by peru from the app-tooling pattern `instruments-profiling`
// (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
// refuses to overwrite a changed copy, and the change belongs in app-tooling.
// docs/app-tooling/instruments-profiling/ says how to use it.
//
// Prefer scenarios the app runs itself (the guide's "Scenarios"): driving
// through the accessibility API adds the driver's own work to the main
// thread being measured. scroll-window and trackpad ask the app nothing.
//
// Drive a Mac app's UI from the command line, through the accessibility API
// and posted events, so a profiling run can exercise the app with no one at
// the keyboard. Needs Accessibility for the process running it (the
// terminal); not screen recording.
//
//   swift scripts/ui-drive.swift tree PID [DEPTH] [--max-children N]
//   swift scripts/ui-drive.swift press PID ROLE NAME [INDEX] [--max-children N]
//                                    AXPress the INDEXth match (default the first)
//   swift scripts/ui-drive.swift scroll PID ROLE [INDEX] [--lines N] [--times K] [--interval-ms M]
//   swift scripts/ui-drive.swift scroll-window PID [--x F] [--y F] [--lines N] [--times K] [--interval-ms M]
//                                    scroll at a point of the app's largest window, given as
//                                    fractions of its width and height (default the centre),
//                                    without touching its accessibility tree
//   swift scripts/ui-drive.swift trackpad PID [--x F] [--y F] [--dx N] [--dy N] [--ms M] [--momentum-ms M]
//                                    a two-finger drag on a trackpad at a point of the largest
//                                    window: continuous pixel scrolling with gesture phases,
//                                    --dx/--dy points per event at 120 Hz for --ms, then
//                                    momentum decaying over --momentum-ms
//   swift scripts/ui-drive.swift keys PID KEY [--times K] [--interval-ms M]
//                                    KEY: up down left right return escape tab delete
//   swift scripts/ui-drive.swift type PID TEXT
//   swift scripts/ui-drive.swift focus PID ROLE [INDEX]  give an element keyboard focus
//
// NAME matches an element's title, description, value or identifier, exactly.
// Scrolling and keys need the window on screen: the app is activated first,
// and scroll events go to wherever the pointer is, which is moved to the
// element's centre.
//
// Compile once rather than paying the interpreter each call:
//   swiftc -O scripts/ui-drive.swift -o build/ui-drive

import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
  return value as? T
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  attribute(element, kAXChildrenAttribute) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
  guard let p: AXValue = attribute(element, kAXPositionAttribute),
    let s: AXValue = attribute(element, kAXSizeAttribute)
  else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  AXValueGetValue(p, .cgPoint, &point)
  AXValueGetValue(s, .cgSize, &size)
  return CGRect(origin: point, size: size)
}

func names(_ element: AXUIElement) -> [String] {
  [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute]
    .compactMap { (attribute(element, $0) as String?) }
    .filter { !$0.isEmpty }
}

// A table's children are all of its rows, visible or not, so a walk is capped
// in breadth as well as depth: ten thousand rows makes the app (and this)
// unresponsive for minutes.
func walk(
  _ element: AXUIElement, depth: Int = 0, maxDepth: Int, maxChildren: Int = 40,
  _ visit: (AXUIElement, Int) -> Bool
) {
  guard visit(element, depth), depth < maxDepth else { return }
  for child in children(element).prefix(maxChildren) {
    walk(child, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren, visit)
  }
}

func find(
  _ app: AXUIElement, role: String, name: String? = nil, index: Int = 0, maxChildren: Int = 40
) -> AXUIElement {
  var matches: [AXUIElement] = []
  walk(app, maxDepth: 40, maxChildren: maxChildren) { element, _ in
    if (attribute(element, kAXRoleAttribute) as String?) == role,
      name.map({ names(element).contains($0) }) ?? true
    {
      matches.append(element)
    }
    return matches.count <= index
  }
  guard matches.count > index else { fail("no \(role)\(name.map { " named \($0)" } ?? "") #\(index)") }
  return matches[index]
}

func option(_ args: [String], _ name: String, _ fallback: Int) -> Int {
  guard let i = args.firstIndex(of: name), i + 1 < args.count, let n = Int(args[i + 1]) else { return fallback }
  return n
}

func fraction(_ args: [String], _ name: String, _ fallback: Double) -> Double {
  guard let i = args.firstIndex(of: name), i + 1 < args.count, let x = Double(args[i + 1]) else { return fallback }
  return x
}

/// The app's largest on-screen window, from the window server: unlike the
/// accessibility API, this asks the app nothing, so it adds no work to it.
func largestWindow(_ pid: pid_t) -> CGRect? {
  let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  return info.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .compactMap { ($0[kCGWindowBounds as String] as! CFDictionary?).flatMap { CGRect(dictionaryRepresentation: $0) } }
    .max { $0.width * $0.height < $1.width * $1.height }
}

func postScroll(at point: CGPoint, _ args: [String]) {
  CGWarpMouseCursorPosition(point)
  let lines = Int32(option(args, "--lines", -5))
  let interval = UInt32(option(args, "--interval-ms", 16)) * 1000
  for _ in 0..<option(args, "--times", 60) {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
    event?.location = point
    event?.post(tap: .cghidEventTap)
    usleep(interval)
  }
}

// A trackpad scroll is continuous (pixel deltas) and carries phases: the
// gesture's began / changed / ended, then the momentum that AppKit would
// generate after the fingers lift. Field numbers are CGEventField's.
let scrollPhaseBegan: Int64 = 1, scrollPhaseChanged: Int64 = 2, scrollPhaseEnded: Int64 = 4
let momentumBegin: Int64 = 1, momentumContinue: Int64 = 2, momentumEnd: Int64 = 3

func postTrackpad(at point: CGPoint, dx: Double, dy: Double, ms: Int, momentumMs: Int) {
  CGWarpMouseCursorPosition(point)
  let interval: UInt32 = 8_333  // 120 Hz
  func post(_ dx: Double, _ dy: Double, scroll: Int64, momentum: Int64) {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()),
        wheel2: Int32(dx.rounded()), wheel3: 0)
    else { return }
    event.location = point
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scroll)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    event.post(tap: .cghidEventTap)
    usleep(interval)
  }
  post(0, 0, scroll: scrollPhaseBegan, momentum: 0)
  for _ in 0..<max(1, ms * 120 / 1000) { post(dx, dy, scroll: scrollPhaseChanged, momentum: 0) }
  post(0, 0, scroll: scrollPhaseEnded, momentum: 0)
  let steps = max(1, momentumMs * 120 / 1000)
  for step in 0..<steps {
    let decay = pow(0.95, Double(step))
    post(dx * decay, dy * decay, scroll: 0, momentum: step == 0 ? momentumBegin : momentumContinue)
  }
  post(0, 0, scroll: 0, momentum: momentumEnd)
}

func activate(_ pid: pid_t) {
  NSRunningApplication(processIdentifier: pid)?.activate()
  usleep(300_000)
}

let keyCodes: [String: CGKeyCode] = [
  "up": 126, "down": 125, "left": 123, "right": 124, "return": 36, "escape": 53, "tab": 48,
  "delete": 51,
]

var args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let pid = pid_t(args[1]) else {
  fail("usage: ui-drive.swift tree|press|scroll|keys|type|focus PID ...")
}
guard AXIsProcessTrusted() else { fail("this process is not trusted for Accessibility") }
let app = AXUIElementCreateApplication(pid)
let positional = args.prefix { !$0.hasPrefix("--") }

switch args[0] {
case "tree":
  let maxDepth = positional.count > 2 ? Int(positional[2]) ?? 8 : 8
  walk(app, maxDepth: maxDepth, maxChildren: option(args, "--max-children", 40)) { element, depth in
    let role: String = attribute(element, kAXRoleAttribute) ?? "?"
    let rect = frame(element).map { " @\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
    let label = names(element).map { String($0.prefix(60)) }.joined(separator: " | ")
    print(String(repeating: "  ", count: depth) + role + (label.isEmpty ? "" : "  \"\(label)\"") + rect)
    return true
  }

case "press":
  guard positional.count >= 4 else { fail("press PID ROLE NAME [INDEX]") }
  let element = find(
    app, role: positional[2], name: positional[3],
    index: positional.count > 4 ? Int(positional[4]) ?? 0 : 0,
    maxChildren: option(args, "--max-children", 40))
  let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
  guard result == .success else { fail("AXPress failed: \(result.rawValue)") }

case "focus":
  guard positional.count >= 3 else { fail("focus PID ROLE [INDEX]") }
  activate(pid)
  let element = find(app, role: positional[2], index: positional.count > 3 ? Int(positional[3]) ?? 0 : 0)
  AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

case "scroll":
  guard positional.count >= 3 else { fail("scroll PID ROLE [INDEX]") }
  activate(pid)
  let element = find(app, role: positional[2], index: positional.count > 3 ? Int(positional[3]) ?? 0 : 0)
  guard let rect = frame(element) else { fail("element has no frame") }
  postScroll(at: CGPoint(x: rect.midX, y: rect.midY), args)

case "scroll-window":
  activate(pid)
  guard let rect = largestWindow(pid) else { fail("no on-screen window for \(pid)") }
  postScroll(
    at: CGPoint(x: rect.minX + rect.width * fraction(args, "--x", 0.5), y: rect.minY + rect.height * fraction(args, "--y", 0.5)),
    args)

case "trackpad":
  activate(pid)
  guard let rect = largestWindow(pid) else { fail("no on-screen window for \(pid)") }
  postTrackpad(
    at: CGPoint(x: rect.minX + rect.width * fraction(args, "--x", 0.5), y: rect.minY + rect.height * fraction(args, "--y", 0.5)),
    dx: fraction(args, "--dx", 0), dy: fraction(args, "--dy", -12), ms: option(args, "--ms", 800),
    momentumMs: option(args, "--momentum-ms", 800))

case "keys":
  guard positional.count >= 3, let code = keyCodes[positional[2]] else {
    fail("keys PID \(keyCodes.keys.sorted().joined(separator: "|"))")
  }
  activate(pid)
  let interval = UInt32(option(args, "--interval-ms", 50)) * 1000
  for _ in 0..<option(args, "--times", 1) {
    for down in [true, false] {
      CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.postToPid(pid)
    }
    usleep(interval)
  }

case "type":
  guard positional.count >= 3 else { fail("type PID TEXT") }
  activate(pid)
  for scalar in positional[2].utf16 {
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
      event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [scalar])
      event?.postToPid(pid)
    }
    usleep(30_000)
  }

default:
  fail("unknown command \(args[0])")
}
