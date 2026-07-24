import Foundation

public enum HistoryStatusColor: Equatable {
    case pending
    case success
    case failure
    case cancelled
    case inProgress
}

public struct HistoryStatusPresentation: Equatable {
    public let symbolName: String
    public let color: HistoryStatusColor

    public init(symbolName: String, color: HistoryStatusColor) {
        self.symbolName = symbolName
        self.color = color
    }
}

public enum HistoryStatus {
    case taskSucceeded
    case taskFailed
    case approvalPending
    case approvalContinuing
    case approvalAllowed
    case approvalDenied
    case inputPending
    case inputSubmitted
    case inputCancelled

    public var presentation: HistoryStatusPresentation {
        switch self {
        case .taskSucceeded:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .taskFailed:
            return HistoryStatusPresentation(symbolName: "xmark.circle.fill", color: .failure)
        case .approvalPending:
            return HistoryStatusPresentation(symbolName: "circle.fill", color: .pending)
        case .approvalContinuing:
            return HistoryStatusPresentation(symbolName: "arrow.triangle.2.circlepath", color: .inProgress)
        case .approvalAllowed:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .approvalDenied:
            return HistoryStatusPresentation(symbolName: "xmark.circle.fill", color: .failure)
        case .inputPending:
            return HistoryStatusPresentation(symbolName: "questionmark.circle.fill", color: .pending)
        case .inputSubmitted:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .inputCancelled:
            return HistoryStatusPresentation(symbolName: "minus.circle.fill", color: .cancelled)
        }
    }
}
