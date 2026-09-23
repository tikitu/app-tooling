import Core
import Foundation

/// The JSON a command inbox holds. The format is documented, with examples,
/// in `docs/commands.md`; `CommandFileTests` decodes those examples verbatim,
/// so the document and the decoder cannot drift apart.
///
/// Strict on purpose: an unknown command or an unknown field is an error, not
/// something ignored, so a typo in a script cannot quietly do nothing.
struct CommandFile: Decodable, Equatable {
    /// Echoed into the result, so a sender can match result to request.
    var id: String?
    var commands: [AppCommand]
}

extension AppCommand: Decodable {
    private enum Name: String, CodingKey, CaseIterable {
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
        let commands = try decoder.container(keyedBy: AnyKey.self)
        guard commands.allKeys.count == 1, let key = commands.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "a command is an object with exactly one key, its name"))
        }
        guard let name = Name(stringValue: key.stringValue) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: commands.codingPath + [key],
                    debugDescription: "unknown command '\(key.stringValue)'; known: "
                        + Name.allCases.map(\.rawValue).sorted().joined(separator: ", ")))
        }
        let unknown = try commands.nestedContainer(keyedBy: AnyKey.self, forKey: key).allKeys.map(
            \.stringValue
        ).filter { !name.fields.contains($0) }
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: commands.codingPath + [key],
                    debugDescription:
                        "unknown field(s) \(unknown.sorted()) for \(name.rawValue); allowed: "
                        + name.fields.sorted().joined(separator: ", ")))
        }

        let fields = try commands.nestedContainer(keyedBy: Field.self, forKey: key)
        func items() throws -> [String] { try fields.decode([String].self, forKey: .items) }
        switch name {
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

/// A coding key for whatever keys an object has, so the decoder can check
/// them against what it expects.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
