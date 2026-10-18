import Foundation

/// Where a split's rotation stands (spec §3, §5): which day the next workout uses.
///
/// Editing the days (adding, deleting, reordering) keeps pointing at the same day where it still
/// exists, so editing a split never silently changes what you train next.
public struct SplitCycle: Equatable, Sendable {
    public private(set) var dayCount: Int
    /// Index of the next day, always in `0..<dayCount` (0 when the split has no days).
    public private(set) var nextDayIndex: Int

    public init(dayCount: Int, nextDayIndex: Int) {
        self.dayCount = max(dayCount, 0)
        self.nextDayIndex = Self.wrap(nextDayIndex, count: self.dayCount)
    }

    /// 1-based position of the next day ("day 2 of 3"), or nil when the split has no days.
    public var position: Int? { dayCount == 0 ? nil : nextDayIndex + 1 }

    /// The cycle after finishing a workout: the following day, wrapping to the first.
    public func advanced() -> SplitCycle {
        SplitCycle(dayCount: dayCount, nextDayIndex: nextDayIndex + 1)
    }

    /// Manually picks the next day (skip or repeat a day).
    public func settingNextDay(_ index: Int) -> SplitCycle {
        SplitCycle(dayCount: dayCount, nextDayIndex: index)
    }

    /// The cycle after inserting a day at `index`.
    public func insertingDay(at index: Int) -> SplitCycle {
        let shifts = dayCount > 0 && index <= nextDayIndex
        return SplitCycle(dayCount: dayCount + 1, nextDayIndex: nextDayIndex + (shifts ? 1 : 0))
    }

    /// The cycle after deleting the day at `index`. Deleting the next day makes the day after it next.
    public func removingDay(at index: Int) -> SplitCycle {
        guard (0..<dayCount).contains(index) else { return self }
        let next = index < nextDayIndex ? nextDayIndex - 1 : nextDayIndex
        return SplitCycle(dayCount: dayCount - 1, nextDayIndex: next)
    }

    /// The cycle after deleting several days at once.
    public func removingDays(at offsets: IndexSet) -> SplitCycle {
        offsets.sorted(by: >).reduce(self) { $0.removingDay(at: $1) }
    }

    /// The cycle after reordering days; the same day stays next.
    public func movingDays(fromOffsets source: IndexSet, toOffset destination: Int) -> SplitCycle {
        let order = Reorder.move(count: dayCount, fromOffsets: source, toOffset: destination)
        let next = order.firstIndex(of: nextDayIndex) ?? nextDayIndex
        return SplitCycle(dayCount: dayCount, nextDayIndex: next)
    }

    private static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index % count) + count) % count
    }
}
