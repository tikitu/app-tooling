import SwiftUI
struct MainWindow: View {
    var body: some View {
        Content().safeAreaInset(edge: .bottom) { Text("bar") } // expect: MainWindow → Content → HSplitView
    }
}
