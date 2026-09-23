/// Where a list's selection goes when the selected rows are acted on, or
/// leave.
///
/// Working through a list means acting on a row and landing on the next one,
/// as Mail does after a delete. So the answer is **the first row after the
/// acted-on ones that is not itself one of them**, falling back to the nearest
/// one before them when they were at the end. `docs/keyboard.md` has the
/// pattern.
public enum SelectionAfter {
    /// `unavailable` are rows that cannot be landed on either — ones that
    /// have gone for some other reason — without being where the search
    /// starts.
    public static func successor<Row: Hashable>(
        of leaving: Set<Row>, in order: [Row], skipping unavailable: Set<Row> = []
    ) -> Row? {
        let indices = order.indices.filter { leaving.contains(order[$0]) }
        guard let first = indices.first, let last = indices.last else { return nil }
        let skip = leaving.union(unavailable)
        if let after = order[(last + 1)...].first(where: { !skip.contains($0) }) { return after }
        return order[..<first].last(where: { !skip.contains($0) })
    }

    /// The selection after the rows changed underneath it — a filter, a
    /// search, a reload.
    ///
    /// Rows still present stay selected. If none are, the selection moves on
    /// as if they had been acted on. Failing that — a new filter took every
    /// neighbour too — and with `selectingFirst`, the first row is selected,
    /// so opening the window or changing the filter puts you straight on
    /// something. Pass `selectingFirst: false` for a list where an empty
    /// selection is the better resting state.
    public static func repaired<Row: Hashable>(
        _ selection: Set<Row>, from old: [Row], to new: [Row], selectingFirst: Bool = true
    ) -> Set<Row> {
        let present = Set(new)
        let surviving = selection.intersection(present)
        if !surviving.isEmpty { return surviving }
        let gone = Set(old.filter { !present.contains($0) })
        if let next = successor(of: selection, in: old, skipping: gone) { return [next] }
        guard selectingFirst else { return [] }
        return new.first.map { [$0] } ?? []
    }
}
