import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import Core

@Suite
struct SchemaTests {
    @Test
    func `the migrated schema stores and reads an item`() throws {
        let database = try DatabaseQueue(path: ":memory:")
        try starterMigrator().migrate(database)
        let added = Date(timeIntervalSince1970: 1_790_000_000)
        try database.write { db in
            try Item.insert { Item.Draft(title: "Buy milk", createdAt: added) }.execute(db)
        }
        let rows = try database.read { db in try Item.fetchAll(db) }
        expectNoDifference(rows.map(\.title), ["Buy milk"])
        expectNoDifference(rows.map(\.createdAt), [added])
        #expect(rows.first?.isDone == false)
    }
}
