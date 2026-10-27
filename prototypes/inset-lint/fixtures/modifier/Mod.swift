import SwiftUI
struct StatusBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) { Text("bar") }
    }
}
extension View {
    func statusBar() -> some View { modifier(StatusBarModifier()) }
    func otherBar() -> some View { self.safeAreaBar(edge: .bottom) { Text("bar") } }
}
struct UsesMod: View {
    var body: some View {
        ModPanes().statusBar() // expect: UsesMod → ModPanes → NavigationSplitView
    }
}
struct UsesMod2: View {
    var body: some View {
        ModPanes().modifier(StatusBarModifier()) // expect: UsesMod2 → ModPanes → NavigationSplitView
    }
}
struct UsesMod3: View {
    var body: some View {
        List { Text("x") }.otherBar() // expect: ok
    }
}
struct ModPanes: View { var body: some View { NavigationSplitView { Text("a") } detail: { Text("b") } } }
