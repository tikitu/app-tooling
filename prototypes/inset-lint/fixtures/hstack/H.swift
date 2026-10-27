import SwiftUI
struct H: View {
    var body: some View {
        HStack { Side(); List { Text("b") } }.safeAreaInset(edge: .bottom) { Text("bar") } // expect: ok
    }
}
struct Side: View { var body: some View { List { Text("a") } } }
