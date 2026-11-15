import Foundation

/// The local model locates evidence; it cannot invent fields in dated email replies.
public enum VerifiedMailReply {
    public static func required(_ plan: MailSearchPlan?) -> Bool {
        plan?.date != nil && plan?.date_scope == "event" && plan?.literal == false
    }
    public static func render(plan: MailSearchPlan, assessment: CompletionAssessment, evidence: [CompletionEvidence]) -> String? {
        guard assessment.complete, assessment.checks.allSatisfy(\.satisfied), required(plan), let date = plan.date else { return nil }
        let variants = plan.date_variants + [date]
        let year = String(date.prefix(4))
        var candidates: [(Int, String)] = []
        for citation in assessment.checks.flatMap(\.evidence) {
            guard let snapshot = evidence.first(where: { $0.id == citation.observation && $0.app == "Mail" }),
                  let row = snapshot.elements.first(where: { $0.id == citation.element }),
                  ["AXCell", "AXStaticText", "AXTextArea", "AXWebArea"].contains(row.role),
                  !citation.quote.isEmpty, [row.label, row.value].contains(where: { $0.contains(citation.quote) }) else { continue }
            var text = row.value.isEmpty ? row.label : row.value
            if let group = row.contentGroup {
                let members = snapshot.elements.filter { $0.contentGroup == group }
                if let parent = members.first(where: { $0.id == group }), !parent.value.isEmpty, parent.value.contains(citation.quote) {
                    text = parent.value
                } else {
                    var parts: [String] = []
                    for item in members where ["AXStaticText", "AXTextArea"].contains(item.role) {
                        let part = item.value.isEmpty ? item.label : item.value
                        if !part.isEmpty, parts.last != part { parts.append(part) }
                    }
                    let expanded = parts.joined(separator: "\n")
                    if expanded.contains(citation.quote) { text = expanded }
                }
            }
            let normalized = MailSearchSession.normalized(text)
            guard text.contains(year), variants.contains(where: {
                let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: MailSearchSession.normalized($0)) + #"(?![\p{L}\p{N}])"#
                return normalized.range(of: pattern, options: .regularExpression) != nil
            }), text.count <= 2400 else { continue }
            // A lone date is not a useful email result.
            var remainder = normalized
            for value in variants + [year, "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "mon", "tue", "wed", "thu", "fri", "sat", "sun"] {
                remainder = remainder.replacingOccurrences(of: MailSearchSession.normalized(value), with: "")
            }
            guard remainder.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            candidates.append((row.contentGroup != nil || row.role == "AXCell" ? 0 : 1, text))
        }
        var excerpts: [String] = []
        for (_, text) in candidates.sorted(by: { $0.0 < $1.0 }) where !excerpts.contains(text) {
            excerpts.append(text)
            if excerpts.count == 2 { break }
        }
        guard !excerpts.isEmpty else { return nil }
        return "From the matching email (\(date)):\n\n" + excerpts.map { "“\($0)”" }.joined(separator: "\n\n")
    }
}
