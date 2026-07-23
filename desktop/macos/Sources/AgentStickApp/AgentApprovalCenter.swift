import Foundation
import AgentStickCore

final class AgentApprovalRequest: Identifiable {
    enum State { case pending, continuing, allowed, denied }

    let id = UUID()
    let agent: String
    let kind: String
    let summary: String
    let details: String
    let createdAt = Date()
    private(set) var state: State = .pending
    private var responder: ((Bool) -> Void)?

    init(agent: String, kind: String, summary: String, details: String, responder: @escaping (Bool) -> Void) {
        self.agent = agent
        self.kind = kind
        self.summary = AgentDisplayTitle.from(
            summary,
            fallback: currentLanguage == .chinese ? "Agent 请求确认" : "Agent requests confirmation"
        )
        self.details = details
        self.responder = responder
    }

    func resolve(allowed: Bool) {
        guard state == .pending else { return }
        state = allowed ? .continuing : .denied
        let callback = responder
        responder = nil
        callback?(allowed)
    }

    func markFinished() {
        guard state == .continuing else { return }
        state = .allowed
    }
}

final class AgentApprovalCenter {
    private(set) var requests: [AgentApprovalRequest] = []
    private(set) var inputRequests: [AgentInputRequest] = []
    var onChange: ((AgentApprovalRequest?) -> Void)?
    var onInputChange: ((AgentInputRequest?) -> Void)?

    @discardableResult
    func submit(agent: String, kind: String, summary: String, details: String, responder: @escaping (Bool) -> Void) -> AgentApprovalRequest {
        let request = AgentApprovalRequest(agent: agent, kind: kind, summary: summary, details: details, responder: responder)
        DispatchQueue.main.async {
            self.requests.insert(request, at: 0)
            self.onChange?(request)
        }
        return request
    }

    func resolve(_ request: AgentApprovalRequest, allowed: Bool) {
        request.resolve(allowed: allowed)
        onChange?(request)
    }

    @discardableResult
    func submitInput(
        agent: String,
        summary: String,
        details: String,
        questions: [AgentInputQuestion],
        responder: @escaping ([String: [String]]?) -> Void
    ) -> AgentInputRequest {
        let request = AgentInputRequest(
            agent: agent,
            summary: summary,
            details: details,
            questions: questions,
            responder: responder
        )
        DispatchQueue.main.async {
            self.inputRequests.insert(request, at: 0)
            self.onInputChange?(request)
        }
        return request
    }

    func resolve(_ request: AgentInputRequest, answers: [String: [String]]?) {
        request.resolve(answers: answers)
        onInputChange?(request)
    }

    func remove(_ request: AgentApprovalRequest) {
        guard request.state != .pending else { return }
        requests.removeAll { $0.id == request.id }
        onChange?(nil)
    }

    func remove(_ request: AgentInputRequest) {
        guard request.state != .pending else { return }
        inputRequests.removeAll { $0.id == request.id }
        onInputChange?(nil)
    }

    func removeResolvedInteractions() {
        requests.removeAll { $0.state != .pending }
        inputRequests.removeAll { $0.state != .pending }
        onChange?(nil)
        onInputChange?(nil)
    }

    func finishContinuingRequests() {
        for request in requests where request.state == .continuing {
            request.markFinished()
        }
        onChange?(nil)
    }
}

struct AgentInputQuestion {
    let id: String
    let header: String
    let question: String
    let options: [String]
    let allowsFreeText: Bool
    let isSecret: Bool
}

final class AgentInputRequest: Identifiable {
    enum State { case pending, submitted, cancelled }
    let id = UUID()
    let agent: String
    let summary: String
    let details: String
    let questions: [AgentInputQuestion]
    let createdAt = Date()
    private(set) var state: State = .pending
    private var responder: (([String: [String]]?) -> Void)?

    init(
        agent: String,
        summary: String,
        details: String,
        questions: [AgentInputQuestion],
        responder: @escaping ([String: [String]]?) -> Void
    ) {
        self.agent = agent
        self.summary = AgentDisplayTitle.from(
            summary,
            fallback: currentLanguage == .chinese ? "Agent 需要输入" : "Agent needs input"
        )
        self.details = details
        self.questions = questions
        self.responder = responder
    }

    func resolve(answers: [String: [String]]?) {
        guard state == .pending else { return }
        state = answers == nil ? .cancelled : .submitted
        let callback = responder
        responder = nil
        callback?(answers)
    }
}
