import Core
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import UI

@MainActor
@Suite(
    .dependencies {
        try $0.bootstrapPreviewDatabase()
        $0.date.now = Date(timeIntervalSince1970: 1_790_000_000)
        $0.uuid = .incrementing
    })
struct ModelTests {
    /// A model with `titles` added, in order, and the list loaded.
    func model(with titles: [String]) async throws -> AppModel {
        let model = AppModel()
        for title in titles { try await model.perform(.add(title: title)) }
        try await model.$items.load()
        return model
    }

    @Test
    func `adding appends and selects the new item`() async throws {
        let model = try await model(with: ["a", "b"])
        expectNoDifference(model.items.map(\.title), ["a", "b"])
        expectNoDifference(model.selectedItems.map(\.title), ["b"])
    }

    @Test
    func `an empty title is refused`() async throws {
        let model = try await model(with: [])
        await #expect(throws: CommandError.emptyTitle) {
            try await model.perform(.add(title: "  "))
        }
    }

    @Test
    func `items are referred to by a title that is exact and unique`() async throws {
        let model = try await model(with: ["a", "b", "b"])
        await #expect(throws: CommandError.noSuchItem("A")) {
            try await model.perform(.select(["A"]))
        }
        await #expect(throws: CommandError.ambiguousTitle("b")) {
            try await model.perform(.select(["b"]))
        }
        try await model.perform(.select(["a"]))
        expectNoDifference(model.selectedItems.map(\.title), ["a"])
    }

    @Test
    func `acting on the selection moves it to the next row`() async throws {
        let model = try await model(with: ["a", "b", "c"])
        try await model.perform(.select(["a"]))
        await model.actOnSelection { .setDone($0, true) }.value
        expectNoDifference(model.selectedItems.map(\.title), ["b"])
        try await model.$items.load()
        expectNoDifference(model.items.filter(\.isDone).map(\.title), ["a"])

        await model.actOnSelection { .delete($0) }.value
        try await model.$items.load()
        expectNoDifference(model.items.map(\.title), ["a", "c"])
        expectNoDifference(model.selectedItems.map(\.title), ["c"])
    }

    @Test
    func `a command that does not wait has finished when attempt returns`() async throws {
        let model = try await model(with: ["a"])
        // Not awaited: a control's action cannot await, and relies on this.
        model.attempt(.select(["a"]))
        expectNoDifference(model.selectedItems.map(\.title), ["a"])
        model.attempt(.select(["nope"]))
        expectNoDifference(model.lastError, "no item 'nope'")
    }

    @Test
    func `hiding done items narrows the list`() async throws {
        let model = try await model(with: ["a", "b"])
        try await model.perform(.setDone(["a"], true))
        try await model.perform(.configure(.init(showsDone: false)))
        try await model.$items.load()
        expectNoDifference(model.visibleItems.map(\.title), ["b"])
        #expect(model.showsDone == false)
    }
}
