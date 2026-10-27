import SwiftUI
struct M: View {
    var body: some View {
        VStack { sidebarArea }.safeAreaInset(edge: .bottom) { Text("bar") } // expect: M → M.sidebarArea → M.split → HSplitView
    }
}
extension M {
    var sidebarArea: some View { self.split }
    @ViewBuilder func split() -> some View { HSplitView { List { Text("a") } } }
}
