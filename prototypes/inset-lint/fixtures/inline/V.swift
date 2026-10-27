import SwiftUI
struct V: View {
    var body: some View {
        HSplitView { List { Text("a") }; List { Text("b") } }
            .safeAreaInset(edge: .bottom) { Text("bar") } // expect: V → HSplitView
    }
}
