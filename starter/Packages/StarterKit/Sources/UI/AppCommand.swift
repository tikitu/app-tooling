import Core
import Foundation

/// Everything a person can do in the app, as a value.
///
/// The buttons, the keys and the menus perform these, and so does
/// ``CommandInbox``, which is how a scripted run drives the app without clicks.
/// Because both go through ``AppModel/perform(_:)``, a script exercises the
/// same code a key press does. **A control that bypasses `perform` is a bug.**
/// Adding one means adding its command, its row in `docs/commands.md`, and its
/// case in the decoder.
///
/// Items are referred to by title, matched exactly. A title more than one
/// item has is an error rather than a guess.
public enum AppCommand: Equatable, Sendable {
    /// Sets any of the remembered options, leaving the others alone. The
    /// controls bind to these directly, as form state; this is the scripted
    /// way to set them.
    case configure(Configuration)

    /// Adds an item at the end of the list and selects it.
    case add(title: String)
    /// Replaces the selection in the list.
    case select([String])
    /// Marks the items done, or not done.
    case setDone([String], Bool)
    /// Deletes the items.
    case delete([String])

    /// The command's name in a command file.
    var name: String {
        switch self {
        case .configure: "configure"
        case .add: "add"
        case .select: "select"
        case .setDone: "setDone"
        case .delete: "delete"
        }
    }
}

extension AppCommand {
    /// The fields of ``configure(_:)``. A `nil` field is left alone.
    public struct Configuration: Equatable, Sendable {
        /// Whether done items are listed.
        public var showsDone: Bool?

        public init(showsDone: Bool? = nil) { self.showsDone = showsDone }
    }
}

public enum CommandError: Error, Equatable, CustomStringConvertible {
    case noSuchItem(String)
    /// More than one item has this title, so it does not say which.
    case ambiguousTitle(String)
    case emptyTitle

    public var description: String {
        switch self {
        case .noSuchItem(let title): "no item '\(title)'"
        case .ambiguousTitle(let title): "more than one item is called '\(title)'"
        case .emptyTitle: "an item needs a title"
        }
    }
}
