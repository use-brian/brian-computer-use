import Foundation

public struct MailSearchPlan: Codable, Equatable, Sendable {
    public let topics: [String]
    public let date: String?
    public let date_scope: String
    public let date_variants: [String]
    public let queries: [String]
    public let literal: Bool
    public init(topics: [String], date: String? = nil, dateScope: String = "none", dateVariants: [String] = [], queries: [String], literal: Bool = false) {
        self.topics = topics; self.date = date; date_scope = dateScope; date_variants = dateVariants; self.queries = queries; self.literal = literal
    }
    public func validate() throws {
        guard (1...3).contains(topics.count), (1...14).contains(queries.count), date_variants.count <= 7,
              ["event", "received", "none"].contains(date_scope),
              (topics + queries + date_variants).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 && $0.unicodeScalars.allSatisfy { $0.value >= 32 } }) else { throw AgentError.invalidAction }
    }
}

/// Search outcomes are observations, never inferred flight facts. Kept only for this run.
public struct MailSearchSession: Codable, Sendable {
    public struct Attempt: Codable, Sendable {
        public let query: String
        public var outcome: String = "awaiting observation"
        public var visibleResults: String = ""
    }
    public let plan: MailSearchPlan?
    public private(set) var attempts: [Attempt] = []
    private var pending = false
    public init(plan: MailSearchPlan?) { self.plan = plan }
    public static func normalized(_ query: String) -> String { query.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    public func tried(_ query: String) -> Bool { attempts.contains { Self.normalized($0.query) == Self.normalized(query) } }
    public var nextQuery: String? { attempts.count < 14 ? plan?.queries.first { !tried($0) } : nil }
    public var needsEmptyConfirmation: Bool { attempts.last?.outcome == "empty (awaiting confirmation)" }
    public var lastWasEmpty: Bool { attempts.last?.outcome == "empty" }
    public func correctedQuery(_ proposed: String) -> String? {
        let words = Set(proposed.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let relativeInsteadOfDate = plan?.date != nil && plan?.literal == false && !words.isDisjoint(with: ["tmr", "tmrw", "tomorrow", "today", "yesterday"])
        // An undated plan cannot gain a date restriction from the calendar,
        // another task, or a later model action.
        let datePattern = #"(?i)\b(?:today|tomorrow|tmr|tmrw|yesterday|(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}|\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?)\b"#
        let inventedDate = plan != nil && plan?.date == nil && plan?.literal == false &&
            proposed.range(of: datePattern, options: .regularExpression) != nil && !(plan?.queries.contains(proposed) ?? false)
        if tried(proposed) || relativeInsteadOfDate || inventedDate { return nextQuery }
        return attempts.count < 14 ? proposed : nil
    }
    public mutating func searched(_ query: String) { attempts.append(Attempt(query: query)); pending = true }
    public mutating func observe(_ observation: DesktopObservation) {
        guard pending, !attempts.isEmpty else { return }
        let query = attempts[attempts.count - 1].query
        guard observation.app == "com.apple.mail", observation.elements.contains(where: {
            ["AXTextField", "AXSearchField", "AXComboBox"].contains($0.role) && Self.normalized($0.value) == Self.normalized(query)
        }) else { return }
        pending = false
        let text = ([observation.window] + observation.elements.filter { !$0.editable }.flatMap { [$0.label, $0.value] }).joined(separator: "\n")
        let empty = text.range(of: #"(?im)^\s*(?:No Results|No Messages Found|0 results)\s*$|\b0 results\b"#, options: .regularExpression) != nil
        let rows = observation.elements.filter { $0.role == "AXRow" && !$0.label.isEmpty && $0.selectable }
        let confirmedEmpty = needsEmptyConfirmation
        attempts[attempts.count - 1].outcome = empty ? (confirmedEmpty ? "empty" : "empty (awaiting confirmation)") : "results require inspection"
        pending = empty && !confirmedEmpty
        attempts[attempts.count - 1].visibleResults = String(([observation.window] + rows.prefix(10).map(\.label)).joined(separator: "\n").prefix(1800))
    }
}
