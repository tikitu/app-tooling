import Core
import Sharing
import SwiftUI

/// The one window: the list, a field to add to it, and a status bar.
public struct MainWindow: View {
    @Bindable
    var model: AppModel

    /// What is being typed into the add field. Form state: what *commits* is
    /// the `add` command.
    @State
    private var newTitle = ""
    @FocusState
    private var isAdding: Bool

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            ItemList(model: model)
            Divider()
            TextField("New item", text: $newTitle).textFieldStyle(.plain).focused($isAdding)
                .onSubmit(add).padding(.horizontal, 12).padding(.vertical, 8)
        }.safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: Binding(model.$showsDone)) {
                    Label("Show Done", systemImage: "checkmark.circle")
                }.help("Show or hide done items")
            }
        }.onChange(of: model.addFieldFocusRequests) { isAdding = true }
    }

    private func add() {
        model.attempt(.add(title: newTitle))
        if model.lastError == nil { newTitle = "" }
    }
}

/// The last error, and a count.
private struct StatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if let error = model.lastError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(countSummary).foregroundStyle(.secondary).monospacedDigit()
        }.font(.callout).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(.bar)
    }

    private var countSummary: String {
        let shown = model.visibleItems.count
        let total = model.items.count
        return shown == total ? "\(total) items" : "\(shown) of \(total) items"
    }
}

/// The Items menu: the window's actions, in the menu bar where the HIG wants
/// every command, with their shortcuts. Each performs the same command its
/// key or context-menu item does.
public struct ItemCommands: Commands {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") { model.requestAddFieldFocus() }.keyboardShortcut("n")
        }
        CommandMenu("Items") {
            Button("Mark Done") { model.actOnSelection { .setDone($0, true) } }.keyboardShortcut(
                .return, modifiers: .command
            ).disabled(model.selection.isEmpty)
            Button("Mark Not Done") { model.actOnSelection { .setDone($0, false) } }.disabled(
                model.selection.isEmpty)
            Divider()
            Button("Delete") { model.actOnSelection { .delete($0) } }.keyboardShortcut(
                .delete, modifiers: .command
            ).disabled(model.selection.isEmpty)
        }
    }
}
