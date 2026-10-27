import SwiftUI
struct Holder: View {
    let panes: STPanes
    var body: some View {
        panes.safeAreaInset(edge: .bottom) { Text("bar") } // expect: Holder → STPanes → HSplitView
    }
}
struct STPanes: View { var body: some View { HSplitView { List { Text("a") } } } }
