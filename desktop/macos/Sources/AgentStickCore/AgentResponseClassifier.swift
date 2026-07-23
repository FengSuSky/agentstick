import Foundation

public enum AgentResponseState: Equatable {
    case completed
    case approvalRequired
    case inputRequired
}

public enum AgentResponseClassifier {
    public static func classify(_ text: String) -> AgentResponseState {
        if text.contains("[AGENTSTICK_INPUT_REQUIRED]") { return .inputRequired }
        if text.contains("[AGENTSTICK_APPROVAL_REQUIRED]") { return .approvalRequired }

        let value = text.lowercased()
        let directApprovalPhrases = [
            "需要你确认", "请批准后", "请确认后", "等待你的确认", "是否允许",
            "need your approval", "please approve", "please confirm", "waiting for your approval",
            "would you like me to"
        ]
        if directApprovalPhrases.contains(where: value.contains) { return .approvalRequired }

        let approvalTerms = [
            "审批", "授权", "权限提示", "权限弹窗", "允许（本次）", "始终允许", "放行",
            "approval", "permission prompt", "permission window", "authorize"
        ]
        let waitingActions = [
            "请在", "点击", "等待", "需要", "之后", "才能继续", "拦截",
            "click", "select allow", "waiting", "before i can", "to continue", "blocked"
        ]
        if approvalTerms.contains(where: value.contains), waitingActions.contains(where: value.contains) {
            return .approvalRequired
        }
        return .completed
    }
}
