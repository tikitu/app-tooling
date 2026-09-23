import CustomDump
import Testing

@testable import UI

@Suite
struct SelectionTests {
    let rows = ["a", "b", "c", "d", "e"]

    @Test
    func `the next row after the acted-on ones`() {
        #expect(SelectionAfter.successor(of: ["b"], in: rows) == "c")
        #expect(SelectionAfter.successor(of: ["b", "c"], in: rows) == "d")
        #expect(SelectionAfter.successor(of: ["b", "d"], in: rows) == "e")
    }

    @Test
    func `at the end, the nearest before`() {
        #expect(SelectionAfter.successor(of: ["e"], in: rows) == "d")
        #expect(SelectionAfter.successor(of: ["d", "e"], in: rows) == "c")
        #expect(SelectionAfter.successor(of: Set(rows), in: rows) == nil)
    }

    @Test
    func `rows that survive a change stay selected`() {
        expectNoDifference(
            SelectionAfter.repaired(["b", "c"], from: rows, to: ["a", "c", "e"]), ["c"])
    }

    @Test
    func `a selection that vanished moves on, skipping rows that went with it`() {
        expectNoDifference(SelectionAfter.repaired(["b"], from: rows, to: ["a", "d", "e"]), ["d"])
    }

    @Test
    func `a new filter that took everything lands on its first row`() {
        expectNoDifference(SelectionAfter.repaired(["b"], from: rows, to: ["x", "y"]), ["x"])
        expectNoDifference(SelectionAfter.repaired([], from: [], to: rows), ["a"])
        expectNoDifference(
            SelectionAfter.repaired([], from: [], to: rows, selectingFirst: false), [])
    }
}
