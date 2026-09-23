import Core
import SwiftUI
import UI

/// The list of items. Keyboard-driven, per `docs/keyboard.md`: it has focus
/// and its first row selected when the window opens; ↑↓ move; Return toggles
/// done; → opens the actions beside the selection; ⌫ deletes. Acting on the
/// selection moves it on to the next row.
struct ItemList: View {
    @Bindable
    var model: AppModel

    /// The row whose action menu is open.
    @State
    private var menuAnchor: Item.ID?
    /// Whether the list has taken focus yet; see the `onChange` below.
    @State
    private var hasTakenFocus = false
    @FocusState
    private var isFocused: Bool

    var body: some View {
        let visible = model.visibleItems
        Table(of: Item.self, selection: $model.selection) {
            TableColumn("Title") { item in
                Text(item.title).strikethrough(item.isDone).foregroundStyle(
                    item.isDone ? .secondary : .primary
                ).actionMenu(at: item.id, anchor: $menuAnchor) { actionMenu() }
            }
            TableColumn("Added") { item in
                Text(item.createdAt, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(.secondary)
            }.width(min: 90, ideal: 130, max: 180)
        } rows: {
            ForEach(visible) { item in TableRow(item) }
        }.contextMenu(forSelectionType: Item.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { _ in
            // Return or a double-click.
            toggleDone()
        }.onKeyPress(.rightArrow) {
            // → opens the actions beside the selection, as it opens a
            // submenu. Nothing to remember: the menu says what there is.
            guard let anchor = visible.first(where: { model.selection.contains($0.id) }) else {
                return .ignored
            }
            menuAnchor = anchor.id
            return .handled
        }.onDeleteCommand {
            // Delete never reaches `onKeyPress` in a Mac list: the list takes
            // it and reports a delete command.
            model.actOnSelection { .delete($0) }
        }.focused($isFocused).onChange(of: visible.map(\.id), initial: true) { old, new in
            model.selection = SelectionAfter.repaired(model.selection, from: old, to: new)
            // The list takes focus once, when the rows first arrive.
            // `defaultFocus` alone is not enough: it is only evaluated when
            // the window becomes key, which a background launch never does
            // (`docs/gotchas.md`).
            if !hasTakenFocus, !new.isEmpty {
                hasTakenFocus = true
                isFocused = true
            }
        }.overlay {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Here Yet", systemImage: "tray")
                } description: {
                    Text(model.items.isEmpty ? "Add an item with ⌘N." : "Every item is done.")
                }
            }
        }
    }

    private var allSelectedAreDone: Bool {
        let selected = model.selectedItems
        return !selected.isEmpty && selected.allSatisfy(\.isDone)
    }

    private func toggleDone() {
        let isDone = allSelectedAreDone
        model.actOnSelection { .setDone($0, !isDone) }
    }

    private func closeMenu() {
        menuAnchor = nil
        isFocused = true
    }

    /// The same things as the right-click menu.
    private func actionMenu() -> ActionMenu {
        let isDone = allSelectedAreDone
        return ActionMenu(
            entries: [
                .init(
                    id: "done", title: isDone ? "Mark Not Done" : "Mark Done",
                    systemImage: isDone ? "circle" : "checkmark.circle"
                ) {
                    closeMenu()
                    toggleDone()
                },
                .init(id: "delete", title: "Delete", systemImage: "trash", isDestructive: true) {
                    closeMenu()
                    model.actOnSelection { .delete($0) }
                },
            ], close: closeMenu)
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Item.ID>) -> some View {
        let titles = model.visibleItems.filter { ids.contains($0.id) }.map(\.title)
        if !titles.isEmpty {
            Button("Mark Done", systemImage: "checkmark.circle") {
                model.attempt(.setDone(titles, true))
            }
            Button("Mark Not Done", systemImage: "circle") {
                model.attempt(.setDone(titles, false))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.attempt(.delete(titles))
            }
        }
    }
}
