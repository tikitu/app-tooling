import Foundation
import IssueReporting
import OSLog

/// Runs commands handed to the app from outside, so a script can drive it
/// without clicks and without taking focus. See `docs/commands.md`.
///
/// A sender writes `inbox.json` into the `Commands` directory of the app's
/// Application Support, then posts the Darwin notification
/// ``notificationName``. The app removes the inbox, runs the commands in
/// order, stopping at the first failure, and writes `result.json` beside it,
/// once the last has finished, however long it waited. An
/// inbox already waiting at launch runs as soon as the app starts.
///
/// **Only started under `--scratch-database`**, so a command can never touch
/// real data or settings (`Entry`).
@MainActor
public final class CommandInbox {
    public static let shared = CommandInbox(
        directory: URL.applicationSupportDirectory.appending(path: "Commands"))
    public static let notificationName = "org.example.starter.commands"

    let directory: URL
    private var model: AppModel?
    private var isObserving = false
    private let logger = Logger(subsystem: "org.example.starter", category: "Commands")

    init(directory: URL) { self.directory = directory }

    var inboxURL: URL { directory.appending(path: "inbox.json") }
    var resultURL: URL { directory.appending(path: "result.json") }

    /// Runs commands against `model` from now on, starting with any inbox
    /// already waiting.
    public func start(model: AppModel) {
        self.model = model
        if !isObserving {
            isObserving = true
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in Task { @MainActor in await CommandInbox.shared.processInbox() }
                }, Self.notificationName as CFString, nil, .deliverImmediately)
        }
        logger.notice(
            "accepting commands in \(self.directory.path(percentEncoded: false), privacy: .public)")
        Task { await processInbox() }
    }

    func processInbox() async {
        guard let model, let data = try? Data(contentsOf: inboxURL) else { return }
        // Taken before its commands run, and not run if it cannot be taken:
        // a command can wait, and a second notification meanwhile would run
        // the same file again.
        guard (try? FileManager.default.removeItem(at: inboxURL)) != nil else { return }
        let result = await Self.run(data, on: model)
        withErrorReporting {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(result).write(to: resultURL, options: .atomic)
            logger.notice(
                "ran \(result.completed.count) command(s)\(result.error.map { "; \($0)" } ?? "", privacy: .public)"
            )
        }
    }

    static func run(_ data: Data, on model: AppModel) async -> CommandResult {
        let file: CommandFile
        do { file = try JSONDecoder().decode(CommandFile.self, from: data) } catch {
            return CommandResult(error: "could not read commands: \(error)")
        }
        var result = CommandResult(requestID: file.id)
        for command in file.commands {
            do {
                let message = try await model.perform(command)
                result.completed.append(.init(command: command.name, message: message))
            } catch {
                result.error = "\(command.name) failed: \(error)"
                break
            }
        }
        return result
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

/// What `result.json` holds. `error` is absent when every command succeeded.
struct CommandResult: Codable, Equatable {
    struct Completed: Codable, Equatable {
        var command: String
        var message: String
    }

    var requestID: String?
    var completed: [Completed] = []
    var error: String?
}
