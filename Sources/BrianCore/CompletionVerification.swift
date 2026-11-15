import Foundation

public struct TaskGoal: Codable, Sendable, Equatable {
    public let objective: String
    public let criteria: [String]
    public let mail_search: MailSearchPlan?
    public init(objective: String, criteria: [String], mailSearch: MailSearchPlan? = nil) { self.objective = objective; self.criteria = criteria; mail_search = mailSearch }
    public func validate() throws {
        try mail_search?.validate()
        guard !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, objective.count <= 12000,
              (1...8).contains(criteria.count), criteria.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 12000 }) else { throw AgentError.invalidAction }
    }
}

/// Bounded, in-memory observations, not model-written summaries or tool success prose.
public struct CompletionEvidence: Codable, Sendable, Equatable {
    public let id: String
    public let app: String
    public let window: String
    public let elements: [DesktopElement]
    public let image: Bool
    public init(id: String, observation: DesktopObservation) {
        self.id = id; app = observation.name; window = observation.window; image = observation.vision != nil
        var remaining = 6000
        var kept: [DesktopElement] = []
        for row in observation.elements {
            let cost = row.label.count + row.value.count + 40
            guard cost <= remaining else { continue }
            remaining -= cost; kept.append(row)
        }
        elements = kept
    }
    func contains(_ citation: EvidenceCitation, currentID: String) -> Bool {
        guard citation.observation == id, !citation.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              citation.quote.count <= 1200 else { return false }
        // Visual citations are independently reviewed against the current image;
        // historical screenshots are never persisted or accepted as current state.
        if citation.element == "image" { return image && id == currentID }
        let sources: [String]
        switch citation.element {
        case "window": sources = [window]
        case "app": sources = [app]
        default:
            guard let row = elements.first(where: { $0.id == citation.element }) else { return false }
            sources = [row.label, row.value]
        }
        return sources.contains { $0.contains(citation.quote) }
    }
}
public struct EvidenceCitation: Codable, Sendable, Equatable {
    public let observation: String
    public let element: String
    public let quote: String
    public init(observation: String, element: String, quote: String) { self.observation = observation; self.element = element; self.quote = quote }
}
public struct CompletionCheck: Codable, Sendable, Equatable {
    public let criterion: Int
    public let satisfied: Bool
    public let evidence: [EvidenceCitation]
    public init(criterion: Int, satisfied: Bool, evidence: [EvidenceCitation]) { self.criterion = criterion; self.satisfied = satisfied; self.evidence = evidence }
}
public struct CompletionAssessment: Codable, Sendable, Equatable {
    public let complete: Bool
    public let reason: String
    public let checks: [CompletionCheck]
    public init(complete: Bool, reason: String, checks: [CompletionCheck]) { self.complete = complete; self.reason = reason; self.checks = checks }
    public func accepts(goal: TaskGoal, evidence: [CompletionEvidence], currentID: String) -> Bool {
        guard complete, !reason.isEmpty, reason.count <= 4000, checks.count == goal.criteria.count,
              Set(checks.map(\.criterion)) == Set(goal.criteria.indices) else { return false }
        return checks.allSatisfy { check in
            check.satisfied && !check.evidence.isEmpty && check.evidence.count <= 8 && check.evidence.allSatisfy { citation in
                evidence.contains { $0.contains(citation, currentID: currentID) }
            }
        }
    }
}
