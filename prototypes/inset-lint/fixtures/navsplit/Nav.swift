import SwiftUI
struct NavRoot: View {
    var body: some View {
        Columns().safeAreaInset(edge: .bottom) { Text("bar") } // expect: NavRoot → Columns → NavigationSplitView
    }
}
struct Columns: View {
    var body: some View {
        NavigationSplitView { List { Text("a") } } detail: { Text("d") }
    }
}
