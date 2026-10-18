import Foundation

/// List reordering shared by every ordered collection the app persists with an `order` field
/// (split days, movement slots, stretch items).
public enum Reorder {
    /// The order of the original indices after moving `source` to `destination`, with the same
    /// meaning as SwiftUI's `move(fromOffsets:toOffset:)`: `destination` is an offset in the list
    /// before the move. `result[i]` is the original index of the element now at position `i`.
    public static func move(count: Int, fromOffsets source: IndexSet, toOffset destination: Int) -> [Int] {
        let indices = Array(0..<count)
        let valid = source.filter { indices.indices.contains($0) }
        let moved = valid.map { indices[$0] }
        var remaining = indices.filter { !valid.contains($0) }
        let insertion = destination - valid.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: min(max(insertion, 0), remaining.count))
        return remaining
    }
}
