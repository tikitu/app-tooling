import AppKit
import SwiftUI

struct Rows: View {
    var body: some View { List(0..<200, id: \.self) { Text("Row \($0)") } }
}
struct Bar: View {
    var body: some View { Text("STATUS").frame(maxWidth: .infinity).padding(6).background(.bar) }
}
struct InlineSplit: View {
    var body: some View {
        VStack(spacing: 0) { HSplitView { Rows(); Rows() } }
            .safeAreaInset(edge: .bottom, spacing: 0) { Bar() }
    }
}
struct Content: View { var body: some View { HSplitView { Rows(); Rows() } } }
struct NestedSplit: View {
    var body: some View { Content().safeAreaInset(edge: .bottom, spacing: 0) { Bar() } }
}
struct NavSplit: View {
    var body: some View {
        NavigationSplitView { Rows() } detail: { Rows() }
            .safeAreaInset(edge: .bottom, spacing: 0) { Bar() }
    }
}
struct NoSplit: View {
    var body: some View { HStack { Rows(); Rows() }.safeAreaInset(edge: .bottom, spacing: 0) { Bar() } }
}
struct TextOnlyBar: View {
    var body: some View {
        HSplitView { Rows(); Rows() }.safeAreaInset(edge: .bottom) { Text("just text") }
    }
}
struct StarterLike: View {
    @State var t = ""
    var body: some View {
        VStack(spacing: 0) { Rows(); TextField("Add", text: $t).padding() }
            .safeAreaInset(edge: .bottom, spacing: 0) { Bar() }
    }
}
struct TableSplit: View {
    struct R: Identifiable { let id: Int }
    var body: some View {
        HSplitView {
            Table((0..<100).map(R.init)) { TableColumn("n") { Text("\($0.id)") } }
            ScrollView { VStack { ForEach(0..<100, id: \.self) { Text("Line \($0)") } } }
        }.safeAreaBar(edge: .bottom) { Bar() }
    }
}
struct OverlayButton: View {
    var body: some View {
        Rows().overlay(alignment: .bottomTrailing) { Button("Add") {}.padding() }
    }
}
struct EmptyOverlay: View {
    var body: some View {
        List { EmptyView() }.overlay { ContentUnavailableView("Nothing", systemImage: "tray") }
    }
}
struct InspectorBar: View {
    var body: some View {
        Rows().inspector(isPresented: .constant(true)) { Rows() }
            .safeAreaInset(edge: .bottom, spacing: 0) { Bar() }
    }
}
struct Stacked: View {
    var body: some View { VStack(spacing: 0) { Content(); Divider(); Bar() } }
}

func dump(_ v: NSView, _ win: NSWindow, _ depth: Int = 0) {
    let r = v.convert(v.bounds, to: nil)
    var extra = ""
    if let s = v as? NSScrollView {
        extra = " contentInsets=\(s.contentInsets) auto=\(s.automaticallyAdjustsContentInsets)"
    }
    let sa = v.safeAreaInsets
    print(String(repeating: "  ", count: depth) + "\(type(of: v)) y=\(r.minY) h=\(r.height) safe=(t\(sa.top) b\(sa.bottom))\(extra)")
    for s in v.subviews { dump(s, win, depth + 1) }
}

@MainActor func probe<V: View>(_ name: String, _ view: V) {
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                       styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    win.contentView = NSHostingView(rootView: view)
    win.orderFront(nil)
    win.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print("=== \(name)")
    let ps = ScrollObstruction.problems(in: win)
    print(ps.isEmpty ? "  ok" : ps.map { "  " + $0.description }.joined(separator: "\n"))
    win.close()
}


let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    probe("InlineSplit", InlineSplit())
    probe("NestedSplit", NestedSplit())
    probe("NavSplit", NavSplit())
    probe("NoSplit", NoSplit())
    probe("Stacked", Stacked())
    probe("InspectorBar", InspectorBar())
    probe("TextOnlyBar", TextOnlyBar())
    probe("StarterLike", StarterLike())
    probe("TableSplit", TableSplit())
    probe("OverlayButton", OverlayButton())
    probe("EmptyOverlay", EmptyOverlay())
}
