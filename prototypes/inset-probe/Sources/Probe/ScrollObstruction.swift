import AppKit

/// Finds scroll views whose last visible line is covered by something drawn
/// on top of them: typically a bar in a `safeAreaInset` that never reached
/// the scroll view (a split view in between drops it).
///
/// For each visible NSScrollView, hit-tests a row of points just inside the
/// bottom (and top) of its unobscured area, its frame less its content
/// insets. A point that hits neither the scroll view nor anything in it is
/// covered by something else.
@MainActor
enum ScrollObstruction {
    struct Problem: CustomStringConvertible {
        let scrollView: NSScrollView
        let edge: String
        let coveredBy: NSView?
        let window: NSWindow
        var description: String {
            let r = scrollView.convert(scrollView.bounds, to: nil)
            return "\(window.title.isEmpty ? "window" : "\"\(window.title)\""): \(edge) of \(type(of: scrollView)) "
                + "at \(NSStringFromRect(r)) is covered (hit \(coveredBy.map { "\(type(of: $0))" } ?? "nothing")), "
                + "insets b\(scrollView.contentInsets.bottom) t\(scrollView.contentInsets.top)"
        }
    }

    static func problems(in windows: [NSWindow] = NSApp.windows) -> [Problem] {
        windows.filter { $0.isVisible && $0.contentView != nil }.flatMap(problems(in:))
    }

    static func problems(in window: NSWindow) -> [Problem] {
        guard let root = window.contentView else { return [] }
        root.layoutSubtreeIfNeeded()
        var found: [Problem] = []
        for scroll in scrollViews(in: root) {
            let frame = scroll.convert(scroll.bounds, to: nil)
            let insets = scroll.contentInsets
            let visible = frame.intersection(root.convert(root.visibleRect, to: nil))
            guard visible.width > 20, visible.height > 20 else { continue }
            let xs = stride(from: 0.02, through: 0.98, by: 0.02).map {
                visible.minX + insets.left + (visible.width - insets.left - insets.right) * $0
            }
            // Window coordinates have y up: bottom is minY.
            let edges = [("bottom", frame.minY + insets.bottom + 2), ("top", frame.maxY - insets.top - 2)]
            for (edge, y) in edges where y > visible.minY && y < visible.maxY {
                let covering = xs.lazy.compactMap { x -> NSView?? in
                    let hit = root.hitTest(root.superview?.convert(NSPoint(x: x, y: y), from: nil) ?? NSPoint(x: x, y: y))
                    if let hit, hit === scroll || hit.isDescendant(of: scroll) { return nil }
                    // A split view's divider takes clicks a few points into the panes beside it.
                    if hit is NSSplitView { return nil }
                    return .some(hit)
                }.first
                if let covering { found.append(Problem(scrollView: scroll, edge: edge, coveredBy: covering, window: window)) }
            }
        }
        return found
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        if view.isHidden { return [] }
        // A scroll view nested in another scroll view's document scrolls with it.
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap(scrollViews(in:))
    }
}
