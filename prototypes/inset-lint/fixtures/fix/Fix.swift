import SwiftUI
struct Fixed: View {
    var body: some View {
        VStack(spacing: 0) { // the fix: bar stacked below the split view, no inset
            Panes2()
            Text("bar")
        }
    }
}
struct Panes2: View { var body: some View { HSplitView { List { Text("a") } } } }
struct Fixed2: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("top").safeAreaInset(edge: .bottom) { Text("x") } // expect: ok
            Panes2()
            Text("bar")
        }
    }
}
