import Core
import Dependencies
import Foundation
import OSLog
import Observation
import SQLiteData
import Sharing
import SwiftUI

private let logger = Logger(subsystem: "org.example.starter", category: "AppModel")

/// The app's state, and the one place commands are performed.
///
/// Every button, key and menu item calls ``perform(_:)`` (through
/// ``attempt(_:)``), and so does ``CommandInbox``. That is what makes a
/// scripted run exercise the same code a key press does. See
/// `docs/commands.md`.
@MainActor
@Observable
public final class AppModel {
    /// The selected rows of the list. Held here rather than in the view so a
    /// script can read it and set it, and so that the menu bar can act on it.
    public var selection: Set<Item.ID> = []

    /// Bumped to ask the window to put the cursor in the add field — ⌘N,
    /// which lives in the menu bar and cannot reach the view's focus.
    public internal(set) var addFieldFocusRequests = 0

    /// The last thing that went wrong, shown in the status bar.
    public internal(set) var lastError: String?

    // Remembered between launches. See `Settings.swift`.
    @ObservationIgnored
    @Shared(.showsDone)
    public var showsDone

    @ObservationIgnored
    @FetchAll(Item.order { ($0.createdAt, $0.id) })
    public var items

    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database
    @ObservationIgnored
    @Dependency(\.date.now)
    private var now
    @ObservationIgnored
    @Dependency(\.uuid)
    private var uuid

    public init() {}

    /// Performs `command` and describes what happened, for a command file's
    /// result.
    ///
    /// Async, so that a command can wait for what it needs (Touch ID, a
    /// dialog, a helper process) and report the outcome, not that it
    /// started. Waiting suspends; it does not block the app. But other
    /// commands can run while one waits, so a command that waits decides
    /// what a second one meanwhile does: refusing it with an error of its
    /// own ("busy") is the usual answer. None of the starter's commands wait.
    @discardableResult
    public func perform(_ command: AppCommand) async throws -> String {
        switch command {
        case .configure(let configuration): return configure(configuration)

        case .add(let title):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw CommandError.emptyTitle }
            let id = uuid()
            let now = self.now
            try write { db in
                try Item.insert { Item.Draft(title: title, createdAt: now, id: id) }.execute(db)
            }
            selection = [id]
            return "added '\(title)'"

        case .select(let titles):
            let resolved = try titles.map(item(titled:))
            selection = Set(resolved.map(\.id))
            return "selected \(resolved.count) item(s)"

        case .setDone(let titles, let isDone):
            let ids = try titles.map(item(titled:)).map(\.id)
            try write { db in
                try Item.where { $0.id.in(ids) }.update { $0.isDone = isDone }.execute(db)
            }
            return "marked \(ids.count) item(s) \(isDone ? "done" : "not done")"

        case .delete(let titles):
            let ids = try titles.map(item(titled:)).map(\.id)
            try write { db in try Item.where { $0.id.in(ids) }.delete().execute(db) }
            selection.subtract(ids)
            return "deleted \(ids.count) item(s)"
        }
    }

    /// The database's synchronous write, on the main actor, as before
    /// `perform` was async. Inside an async function `database.write` is the
    /// async overload, which suspends, so a command that only writes would
    /// no longer have finished when ``attempt(_:)`` returns.
    private func write(_ updates: (Database) throws -> Void) throws { try database.write(updates) }

    private func configure(_ configuration: AppCommand.Configuration) -> String {
        var changed: [String] = []
        if let showsDone = configuration.showsDone {
            $showsDone.withLock { $0 = showsDone }
            changed.append("showsDone")
        }
        return changed.isEmpty ? "nothing to configure" : "set \(changed.joined(separator: ", "))"
    }

    /// An item by its title, which has to be exact and unique.
    func item(titled title: String) throws -> Item {
        let matches = items.filter { $0.title == title }
        guard let match = matches.first else { throw CommandError.noSuchItem(title) }
        guard matches.count == 1 else { throw CommandError.ambiguousTitle(title) }
        return match
    }
}

// MARK: - What the views read

extension AppModel {
    /// The list as shown.
    public var visibleItems: [Item] { showsDone ? items : items.filter { !$0.isDone } }

    /// The selected items, in list order.
    public var selectedItems: [Item] { visibleItems.filter { selection.contains($0.id) } }

    public func requestAddFieldFocus() { addFieldFocusRequests += 1 }
}

extension AppModel {
    /// Performs a command from a control, reporting a failure in the status
    /// bar rather than throwing into SwiftUI.
    ///
    /// Controls call this; ``CommandInbox`` calls `perform` directly, because
    /// a command file wants the error in its result.
    ///
    /// Returns at once, so a control's action can call it, with the task
    /// doing the work: `await model.attempt(…).value` for the outcome. The
    /// task starts immediately, so a command that does not wait has finished
    /// by the time this returns.
    @discardableResult
    public func attempt(_ command: AppCommand) -> Task<Void, Never> {
        Task.immediate { await run(command) }
    }

    private func run(_ command: AppCommand) async {
        do {
            lastError = nil
            try await perform(command)
        } catch {
            logger.error("\(command.name) failed: \(error)")
            lastError = "\(error)"
        }
    }

    /// Performs a command on the selected items, then moves the selection to
    /// the next row — "acting moves on" (`docs/keyboard.md`). Returns at once,
    /// as ``attempt(_:)`` does.
    @discardableResult
    public func actOnSelection(_ command: ([String]) -> AppCommand) -> Task<Void, Never> {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return Task {} }
        // Worked out before the command runs, from the list as the person saw
        // it when they acted: once it has run, the acted-on rows may be gone.
        let next = SelectionAfter.successor(of: selection, in: visibleItems.map(\.id))
        let command = command(chosen.map(\.title))
        return Task.immediate {
            await run(command)
            selection = next.map { [$0] } ?? []
        }
    }
}
