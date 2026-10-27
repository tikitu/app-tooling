import SwiftUI
import Feature
public struct Root: View {
    public var body: some View {
        Shell().safeAreaBar(edge: .top) { Text("bar") } // expect: Root → Shell → Panes → VSplitView
    }
}
