import Foundation

public enum AgentResponseState: Equatable {
    case completed
    case approvalRequired
    case inputRequired
}

public enum AgentResponseClassifier {
    public static func classify(_ text: String) -> AgentResponseState {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("[AGENTSTICK_INPUT_REQUIRED]") { return .inputRequired }
        if value.hasPrefix("[AGENTSTICK_APPROVAL_REQUIRED]") { return .approvalRequired }
        return .completed
    }
}
