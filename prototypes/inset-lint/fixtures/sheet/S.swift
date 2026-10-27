import SwiftUI
struct S: View {
    @State var shown = false
    var body: some View {
        List { Text("a") }
            .sheet(isPresented: $shown) { SheetPanes() }
            .safeAreaInset(edge: .bottom) { Text("bar") } // expect: ok (sheet content is presented elsewhere)
    }
}
struct SheetPanes: View { var body: some View { HSplitView { List { Text("a") } } } }
