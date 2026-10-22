import CommandInbox
import Core
import Foundation

/// How an `AppCommand` is written in a command file. The format is
/// documented, with examples, in `docs/commands.md`; `CommandFileTests`
/// decodes those examples verbatim, so the document and the decoder cannot
/// drift apart.
///
/// Strict on purpose (``StrictCommand``): an unknown command or an unknown
/// field is an error, not something ignored, so a typo in a script cannot
/// quietly do nothing.
extension AppCommand: InboxCommand {
    private enum Name: String, CommandName {
        case configure, add, select, setDone, delete

        var fields: Set<String> {
            switch self {
            case .configure: ["showsDone"]
            case .add: ["title"]
            case .select, .delete: ["items"]
            case .setDone: ["items", "done"]
            }
        }
    }

    private enum Field: String, CodingKey { case showsDone, title, items, done }

    public init(from decoder: any Decoder) throws {
        let command = try StrictCommand<Name>(from: decoder)
        let fields = try command.fields(keyedBy: Field.self)
        func items() throws -> [String] { try fields.decode([String].self, forKey: .items) }
        switch command.name {
        case .configure:
            self = .configure(
                Configuration(showsDone: try fields.decodeIfPresent(Bool.self, forKey: .showsDone)))
        case .add: self = .add(title: try fields.decode(String.self, forKey: .title))
        case .select: self = .select(try items())
        case .setDone:
            self = .setDone(
                try items(), try fields.decodeIfPresent(Bool.self, forKey: .done) ?? true)
        case .delete: self = .delete(try items())
        }
    }
}
