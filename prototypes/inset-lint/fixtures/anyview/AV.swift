import SwiftUI
struct AV: View {
    var body: some View {
        AnyView(AVPanes()).safeAreaInset(edge: .bottom) { Text("bar") } // expect: AV → AVPanes → HSplitView
    }
}
struct AVPanes: View { var body: some View { HSplitView { List { Text("a") } } } }
