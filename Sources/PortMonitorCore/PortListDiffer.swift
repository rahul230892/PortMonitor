import Foundation

/// What changed between two refreshes, plus the sockets that just appeared.
public struct PortListUpdate: Equatable, Sendable {
    /// Sockets present now that were not present in the previous sample.
    public let added: [PortInfo]
    /// Sockets present previously that are gone now.
    public let removed: [PortInfo]
    /// Ids of ``added`` sockets, for highlighting.
    public let addedIDs: Set<String>
    /// True for the very first sample, when there is nothing to compare against.
    public let isInitialLoad: Bool

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// Tracks successive samples of open sockets and reports the delta.
///
/// Kept free of UI and timers so the "what is new since last refresh?"
/// behaviour can be unit tested directly.
public struct PortListDiffer: Sendable {
    private var known: [PortInfo] = []
    private var knownIDs: Set<String> = []
    private var hasLoadedOnce = false

    public init() {}

    /// Folds a new sample in and returns what changed.
    ///
    /// The first call reports `isInitialLoad == true` with no `addedIDs`, so the
    /// whole list is not flashed as "new" on launch.
    @discardableResult
    public mutating func apply(_ items: [PortInfo]) -> PortListUpdate {
        let ids = Set(items.map(\.id))

        guard hasLoadedOnce else {
            known = items
            knownIDs = ids
            hasLoadedOnce = true
            return PortListUpdate(added: items, removed: [], addedIDs: [], isInitialLoad: true)
        }

        let addedIDs = ids.subtracting(knownIDs)
        let removedIDs = knownIDs.subtracting(ids)

        let added = items.filter { addedIDs.contains($0.id) }
        let removed = known.filter { removedIDs.contains($0.id) }

        known = items
        knownIDs = ids

        return PortListUpdate(
            added: added,
            removed: removed,
            addedIDs: addedIDs,
            isInitialLoad: false
        )
    }

    /// Forgets all history so the next ``apply(_:)`` behaves like a first load.
    public mutating func reset() {
        known = []
        knownIDs = []
        hasLoadedOnce = false
    }
}
