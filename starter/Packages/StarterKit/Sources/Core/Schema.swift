import Dependencies
import Foundation
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "org.example.starter", category: "Database")

/// A thing on the list. A placeholder for the app's real data: it is here so
/// that the database, the commands, the keyboard and the tests have something
/// to work on. Replace it, and its migration, when the real model exists.
@Table
public struct Item: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var createdAt: Date
}

extension DependencyValues {
    /// A migrated, empty, in-memory database, for previews and tests.
    ///
    /// It runs the *real* migrator, so a preview sees the schema the app
    /// sees. Previews that install nothing read SQLiteData's blank `:memory:`
    /// fallback and show an empty screen that looks like "no data yet" — see
    /// `plans/gotchas.md`.
    public mutating func bootstrapPreviewDatabase(seed: ((Database) throws -> Void)? = nil) throws {
        let database = try DatabaseQueue(path: ":memory:")
        try starterMigrator().migrate(database)
        if let seed { try database.write(seed) }
        defaultDatabase = database
    }

    /// Opens the app's database, migrating it, and installs it.
    ///
    /// `scratch: true` opens a disposable copy under the app's `tmp`
    /// directory. That is the only mode in which the app accepts commands
    /// (`--scratch-database`), so a script can never touch real data.
    public mutating func bootstrapDatabase(scratch: Bool = false) throws {
        let url = try starterDatabaseURL(scratch: scratch)
        // `path(percentEncoded: false)`, not `path()`: the RFC 3986 accessor
        // keeps the escaping, and "Application Support" arrives at SQLite as
        // "Application%20Support". See `plans/gotchas.md`.
        let path = url.path(percentEncoded: false)
        logger.notice("database at \(path, privacy: .public)")

        var configuration = Configuration()
        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) { logger.debug("\($0.expandedDescription)") }
        }
        #endif
        let database = try DatabaseQueue(path: path, configuration: configuration)
        try starterMigrator().migrate(database)
        defaultDatabase = database
    }
}

/// Where the database file lives. Application Support, which under the
/// sandbox is inside the app's container.
public func starterDatabaseURL(scratch: Bool = false) throws -> URL {
    let directory =
        scratch
        ? URL.temporaryDirectory.appending(path: "Starter-scratch", directoryHint: .isDirectory)
        : URL.applicationSupportDirectory.appending(path: "Starter", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: scratch ? "scratch.sqlite" : "Starter.sqlite")
}

/// The schema, in one place. The real database and the in-memory one previews
/// and tests use both run exactly this.
///
/// `eraseDatabaseOnSchemaChange` is deliberately **not** set, even in DEBUG:
/// `make run` is a debug build against the real data. Add a migration; never
/// edit one that has run. `semgrep/docs/erase-on-schema-change.md`.
public func starterMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1_items") { db in
        try #sql(
            """
            CREATE TABLE "items" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL,
                "isDone" INTEGER NOT NULL DEFAULT 0,
                "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT CURRENT_TIMESTAMP
            ) STRICT
            """
        ).execute(db)
    }

    return migrator
}

extension Item.Draft {
    /// A new item, not done. The generated memberwise initialiser is internal
    /// to `Core`; `id` is for callers that need to know it in advance.
    public init(title: String, createdAt: Date, id: UUID? = nil) {
        self.init(id: id, title: title, isDone: false, createdAt: createdAt)
    }
}
