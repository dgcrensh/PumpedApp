import Foundation
import PumpedCore
import SwiftData

/// The split editor's mutations, kept out of the views so they can be unit tested.
///
/// Every ordered collection is renumbered `0..<count` after a change, and edits to a split's days
/// go through `SplitCycle` so the day that's "next up" stays the same day.
@MainActor
enum SplitEditing {
    /// Id of the seeded sequence new split days use for their cool-down.
    static let defaultStretchSequenceID = "full-body"

    // MARK: Splits

    /// Creates a split. The first split becomes active.
    @discardableResult
    static func createSplit(named name: String, in context: ModelContext) -> Split {
        let activeCount = (try? context.fetchCount(FetchDescriptor<Split>(predicate: #Predicate { $0.isActive }))) ?? 0
        let split = Split(name: name, isActive: activeCount == 0)
        context.insert(split)
        return split
    }

    /// Makes `split` the only active split.
    static func setActive(_ split: Split, in context: ModelContext) {
        let splits = (try? context.fetch(FetchDescriptor<Split>())) ?? []
        for other in splits { other.isActive = other === split }
        split.isActive = true
    }

    /// Deletes a split. If it was active, the most recently created remaining split takes over.
    static func deleteSplit(_ split: Split, in context: ModelContext) {
        let wasActive = split.isActive
        context.delete(split)
        guard wasActive else { return }
        let remaining = ((try? context.fetch(FetchDescriptor<Split>())) ?? [])
            .filter { $0 !== split && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
        remaining.first?.isActive = true
    }

    // MARK: Days

    @discardableResult
    static func addDay(named name: String, to split: Split, in context: ModelContext) -> SplitDay {
        let days = split.orderedDays
        let day = SplitDay(name: name, order: days.count)
        context.insert(day)
        day.stretchSequence = stretchSequence(id: defaultStretchSequenceID, in: context)
        let cycle = SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex).insertingDay(at: days.count)
        split.days.append(day)
        split.nextDayIndex = cycle.nextDayIndex
        return day
    }

    static func deleteDays(at offsets: IndexSet, from split: Split, in context: ModelContext) {
        let days = split.orderedDays
        let cycle = SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex).removingDays(at: offsets)
        let doomed = offsets.filter { days.indices.contains($0) }.map { days[$0] }
        split.days.removeAll { day in doomed.contains { $0 === day } }
        for day in doomed { context.delete(day) }
        renumber(split.orderedDays) { $0.order = $1 }
        split.nextDayIndex = cycle.nextDayIndex
    }

    static func moveDays(of split: Split, fromOffsets source: IndexSet, toOffset destination: Int) {
        let days = split.orderedDays
        let cycle = SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex)
            .movingDays(fromOffsets: source, toOffset: destination)
        apply(Reorder.move(count: days.count, fromOffsets: source, toOffset: destination), to: days) { $0.order = $1 }
        split.nextDayIndex = cycle.nextDayIndex
    }

    /// Manually picks the day the next workout uses (skip or repeat a day).
    static func setNextDay(_ day: SplitDay, of split: Split) {
        guard let index = split.orderedDays.firstIndex(where: { $0 === day }) else { return }
        split.nextDayIndex = SplitCycle(dayCount: split.days.count, nextDayIndex: split.nextDayIndex)
            .settingNextDay(index).nextDayIndex
    }

    /// The day the next workout uses, if the split has any days.
    static func nextDay(of split: Split) -> SplitDay? {
        let days = split.orderedDays
        guard !days.isEmpty else { return nil }
        return days[SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex).nextDayIndex]
    }

    // MARK: Movement slots

    /// Appends a slot. The same movement type may appear more than once.
    @discardableResult
    static func addSlot(_ movementType: MovementType, to day: SplitDay, in context: ModelContext) -> MovementSlot {
        let slot = MovementSlot(movementType: movementType, order: day.slots.count)
        context.insert(slot)
        day.slots.append(slot)
        return slot
    }

    static func deleteSlots(at offsets: IndexSet, from day: SplitDay, in context: ModelContext) {
        let slots = day.orderedSlots
        let doomed = offsets.filter { slots.indices.contains($0) }.map { slots[$0] }
        day.slots.removeAll { slot in doomed.contains { $0 === slot } }
        for slot in doomed { context.delete(slot) }
        renumber(day.orderedSlots) { $0.order = $1 }
    }

    static func moveSlots(of day: SplitDay, fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = day.orderedSlots
        apply(Reorder.move(count: slots.count, fromOffsets: source, toOffset: destination), to: slots) { $0.order = $1 }
    }

    // MARK: Stretch sequences

    @discardableResult
    static func createSequence(named name: String, in context: ModelContext) -> StretchSequence {
        let sequence = StretchSequence(name: name)
        context.insert(sequence)
        return sequence
    }

    /// Copies a sequence (typically a read-only default) into a new editable one.
    @discardableResult
    static func duplicateSequence(_ source: StretchSequence, in context: ModelContext) -> StretchSequence {
        let copy = StretchSequence(name: "\(source.name) copy")
        context.insert(copy)
        for (offset, item) in source.orderedItems.enumerated() {
            let newItem = StretchItem(stretch: item.stretch, durationSec: item.durationSec, order: offset)
            context.insert(newItem)
            copy.items.append(newItem)
        }
        return copy
    }

    /// Deletes a user-defined sequence. Split days that used it are left without a cool-down sequence.
    static func deleteSequence(_ sequence: StretchSequence, in context: ModelContext) {
        guard !sequence.isDefault else { return }
        let days = (try? context.fetch(FetchDescriptor<SplitDay>())) ?? []
        for day in days where day.stretchSequence === sequence { day.stretchSequence = nil }
        context.delete(sequence)
    }

    @discardableResult
    static func addStretch(_ stretch: Stretch, to sequence: StretchSequence, in context: ModelContext) -> StretchItem? {
        guard !sequence.isDefault else { return nil }
        let item = StretchItem(stretch: stretch, durationSec: stretch.defaultDurationSec, order: sequence.items.count)
        context.insert(item)
        sequence.items.append(item)
        return item
    }

    static func deleteStretches(at offsets: IndexSet, from sequence: StretchSequence, in context: ModelContext) {
        guard !sequence.isDefault else { return }
        let items = sequence.orderedItems
        let doomed = offsets.filter { items.indices.contains($0) }.map { items[$0] }
        sequence.items.removeAll { item in doomed.contains { $0 === item } }
        for item in doomed { context.delete(item) }
        renumber(sequence.orderedItems) { $0.order = $1 }
    }

    static func moveStretches(of sequence: StretchSequence, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !sequence.isDefault else { return }
        let items = sequence.orderedItems
        apply(Reorder.move(count: items.count, fromOffsets: source, toOffset: destination), to: items) { $0.order = $1 }
    }

    // MARK: Helpers

    private static func stretchSequence(id: String, in context: ModelContext) -> StretchSequence? {
        try? context.fetch(FetchDescriptor<StretchSequence>(predicate: #Predicate { $0.id == id })).first
    }

    /// Writes positions so that the element at `order[i]` gets position `i`.
    private static func apply<Element>(_ order: [Int], to elements: [Element], setOrder: (Element, Int) -> Void) {
        for (position, original) in order.enumerated() { setOrder(elements[original], position) }
    }

    private static func renumber<Element>(_ elements: [Element], setOrder: (Element, Int) -> Void) {
        for (position, element) in elements.enumerated() { setOrder(element, position) }
    }
}
