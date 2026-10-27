import SwiftUI
struct L: View {
    var body: some View {
        let panes = LPanes()
        return panes.safeAreaInset(edge: .bottom) { Text("bar") } // expect: L → LPanes → VSplitView
    }
}
struct LPanes: View { var body: some View { VSplitView { List { Text("a") } } } }
