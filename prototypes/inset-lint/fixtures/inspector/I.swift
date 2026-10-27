import SwiftUI
struct I: View {
    @State var shown = true
    var body: some View {
        List { Text("a") }
            .inspector(isPresented: $shown) { InspectorPanes() }
            .safeAreaInset(edge: .bottom) { Text("bar") } // expect: I → .inspector
    }
}
struct InspectorPanes: View { var body: some View { VSplitView { List { Text("a") } } } }
