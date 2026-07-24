import Foundation

public struct HistoryGroupingItem: Equatable {
    public let id: String
    public let isPending: Bool
    public let date: Date

    public init(id: String, isPending: Bool, date: Date) {
        self.id = id
        self.isPending = isPending
        self.date = date
    }
}

public struct HistoryGroupedResult: Equatable {
    public let pending: [HistoryGroupingItem]
    public let history: [HistoryGroupingItem]

    public init(pending: [HistoryGroupingItem], history: [HistoryGroupingItem]) {
        self.pending = pending
        self.history = history
    }
}

public enum HistoryEntryGrouping {
    public static func group(_ items: [HistoryGroupingItem]) -> HistoryGroupedResult {
        let pending = items.filter(\.isPending).sorted { $0.date > $1.date }
        let history = items.filter { !$0.isPending }.sorted { $0.date > $1.date }
        return HistoryGroupedResult(pending: pending, history: history)
    }
}
