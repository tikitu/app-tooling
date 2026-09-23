import Core
import Dependencies
import Foundation
import IssueReporting
import MacUI
import SQLiteData
import SwiftUI
import UI

/// The entry point is an `enum`, not the `App`, and the dependencies are
/// prepared *before* `StarterApp.main()` is called.
///
/// This is not a style choice. `prepareDependencies` applies only to
/// dependencies that have not yet been read, and something in SwiftUI's macOS
/// startup path resolves `defaultDatabase` before `App.init()` runs — so
/// bootstrapping there is silently ignored and every `@FetchAll` reads
/// SQLiteData's blank `:memory:` fallback. `docs/gotchas.md` has the details.
/// Do not "simplify" this into `App.init()`.
@main
enum Entry {
    /// `--scratch-database` runs on a disposable database and its own user
    /// defaults, and accepts commands. The real app does neither — see
    /// `docs/commands.md`.
    static let isScratch = CommandLine.arguments.contains("--scratch-database")

    /// Made here rather than in the `App`, for the same ordering reason: a
    /// scratch run has to accept commands from launch, and a view's `.task`
    /// never runs while the app is in the background, which is exactly how
    /// `make run-scratch` starts it.
    @MainActor
    static let model = AppModel()

    static func main() {
        withErrorReporting {
            try prepareDependencies {
                try $0.bootstrapDatabase(scratch: isScratch)
                if isScratch, let defaults = UserDefaults(suiteName: "org.example.starter.scratch")
                {
                    $0.defaultAppStorage = defaults
                }
            }
        }
        MainActor.assumeIsolated {
            // Started from here, not a view's `.task`, for the reason above.
            if isScratch { CommandInbox.shared.start(model: model) }
        }
        StarterApp.main()
    }
}

struct StarterApp: App {
    var body: some Scene {
        Window("Starter App", id: "main") { MainWindow(model: Entry.model) }.defaultSize(
            width: 640, height: 480
        ).commands { ItemCommands(model: Entry.model) }
    }
}
