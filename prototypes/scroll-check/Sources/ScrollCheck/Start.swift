import AppKit
import Foundation

/// Runs the check in the host app once its windows are up, then reports on
/// stderr and quits. SCROLL_CHECK_DELAY (seconds, default 4) waits for them.
@_cdecl("scrollCheckStart")
public func scrollCheckStart() {
    let delay = Double(ProcessInfo.processInfo.environment["SCROLL_CHECK_DELAY"] ?? "") ?? 4
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        MainActor.assumeIsolated {
            let windows = NSApp.windows.filter(\.isVisible)
            let problems = ScrollObstruction.problems(in: windows)
            var out = "scroll-check: \(windows.count) window(s), \(problems.count) problem(s)\n"
            for p in problems { out += "  \(p)\n" }
            for w in windows { out += "  window \(w.windowNumber) \"\(w.title)\"\n" }
            FileHandle.standardError.write(Data(out.utf8))
            if ProcessInfo.processInfo.environment["SCROLL_CHECK_HOLD"] != nil {
                // Scroll each flagged view to its end, for a screenshot.
                for p in problems {
                    if let doc = p.scrollView.documentView {
                        let y = doc.isFlipped ? doc.bounds.maxY : doc.bounds.minY
                        doc.scroll(NSPoint(x: 0, y: y))
                    }
                }
                return
            }
            exit(problems.isEmpty ? 0 : 3)
        }
    }
}
