import SwiftUI
public struct Panes: View {
    public init() {}
    public var body: some View { VSplitView { List { Text("a") }; List { Text("b") } } }
}
