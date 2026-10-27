import SwiftUI
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.safeAreaInset(edge: .bottom) { Text("card bar") } // expect: Card → Card#callers → WPanes → HSplitView
    }
}
struct UsesCard: View {
    var body: some View {
        Card { WPanes() }
    }
}
struct WPanes: View { var body: some View { HSplitView { List { Text("a") } } } }
struct Frame<C: View>: View {
    @ViewBuilder let c: C
    var body: some View { c.padding() }
}
struct UsesFrame: View {
    var body: some View {
        Frame { Text("only text") }.safeAreaInset(edge: .bottom) { Text("bar") } // expect: ok
    }
}
