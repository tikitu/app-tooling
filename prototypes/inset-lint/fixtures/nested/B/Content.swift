import SwiftUI
struct Content: View {
    var body: some View {
        HSplitView { List { Text("a") }; List { Text("b") } }
    }
}
