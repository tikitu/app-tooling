import Core
import CustomDump
import Foundation
import Testing

@testable import UI

@Suite
struct CommandFileTests {
    /// Every JSON block in `docs/commands.md` that holds `"commands"`, which
    /// are the request examples. Read from the document itself, so the
    /// document cannot drift from the decoder.
    static let documentedRequests: [String] = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(
            path: "../../../../docs/commands.md")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "```json\n").dropFirst().compactMap { block in
            let json = block.components(separatedBy: "```").first ?? ""
            return json.contains("\"commands\"") ? json : nil
        }
    }()

    @Test
    func `the document has request examples`() { #expect(Self.documentedRequests.count == 2) }

    @Test(arguments: documentedRequests)
    func `every documented request decodes`(json: String) throws {
        _ = try JSONDecoder().decode(CommandFile.self, from: Data(json.utf8))
    }

    @Test
    func `the first example decodes to what it says`() throws {
        let file = try JSONDecoder().decode(
            CommandFile.self, from: Data(Self.documentedRequests[0].utf8))
        expectNoDifference(
            file.commands,
            [
                .add(title: "Buy milk"), .add(title: "Call the plumber"),
                .setDone(["Buy milk"], true),
            ])
    }

    @Test(arguments: [
        #"{"commands":[{"ad":{"title":"x"}}]}"#, #"{"commands":[{"add":{"name":"x"}}]}"#,
        #"{"commands":[{"add":{"title":"x"},"delete":{"items":["x"]}}]}"#,
    ])
    func `typos are errors, not silently ignored`(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CommandFile.self, from: Data(json.utf8))
        }
    }
}
