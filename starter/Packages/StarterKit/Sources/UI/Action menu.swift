import SwiftUI

/// A keyboard menu in a popover: ↑↓ move, Return performs, ← or Esc closes, a
/// click performs. A real `NSMenu` would do this for free, but SwiftUI cannot
/// open one from a key press; a list in a popover is the nearest thing that
/// takes focus reliably. See `docs/keyboard.md`.
struct ActionMenu: View {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        var isDestructive = false
        let perform: () -> Void
    }

    let entries: [Entry]
    let close: () -> Void

    @State
    private var highlighted: Entry.ID?
    @FocusState
    private var isFocused: Bool

    var body: some View {
        List(entries, selection: $highlighted) { entry in
            Label(entry.title, systemImage: entry.systemImage).foregroundStyle(
                entry.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
            ).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect).onTapGesture {
                entry.perform()
            }
        }.listStyle(.plain).scrollDisabled(true).scrollContentBackground(.hidden).frame(
            width: 230, height: CGFloat(entries.count) * 28 + 10
        ).focused($isFocused).defaultFocus($isFocused, true).onAppear {
            highlighted = entries.first?.id
        }.onKeyPress(.return) {
            entries.first { $0.id == highlighted }?.perform()
            return .handled
        }.onKeyPress(.leftArrow) {
            close()
            return .handled
        }
    }
}

extension View {
    /// Offers the action menu beside a row while `anchor` is that row.
    func actionMenu<Row: Hashable>(
        at row: Row, anchor: Binding<Row?>, @ViewBuilder menu: @escaping () -> ActionMenu
    ) -> some View {
        popover(
            isPresented: Binding(
                get: { anchor.wrappedValue == row },
                set: { isOpen in
                    if !isOpen, anchor.wrappedValue == row { anchor.wrappedValue = nil }
                }), arrowEdge: .trailing, content: menu)
    }
}
