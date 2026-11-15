import Foundation

/// Route explicit email searches before the generic web-search launcher.
/// This is a deterministic local capability, not an extension of the AX model.
public struct MailSearchRequest: Equatable, Sendable {
    public let query: String

    public init(query: String) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 500,
              query.unicodeScalars.allSatisfy({ $0.value >= 32 }) else { throw MailSearchError.invalidQuery }
        self.query = query
    }

    public static func parse(_ input: String) throws -> Self? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"^(?:search the web|google|open|launch|go to)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        guard text.range(of: #"\b(?:e-?mails?|mail)\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        guard text.count <= 500, !text.contains(where: { $0.isNewline }),
              text.unicodeScalars.allSatisfy({ $0.value >= 32 }) else { throw MailSearchError.invalidQuery }
        let prefix = #"^(?:(?:please|can you|could you|help me)\s+)*(?:find|search(?:\s+for)?|look for|show(?:\s+me)?|locate)\s+"#
        guard let range = text.range(of: prefix, options: [.regularExpression, .caseInsensitive]) else {
            throw MailSearchError.unsupported
        }
        var body = String(text[range.upperBound...])
        body = body.replacingOccurrences(of: #"^(?:(?:my|the|all|latest|newest|recent)\s+)+"#,
                                         with: "", options: [.regularExpression, .caseInsensitive])
        let patterns = [
            #"^(?:e-?mails?|mail)\s+(?:(?:for|from|about|containing)\s+)?(.+?)\s*$"#,
            #"^(.+?)\s+(?:e-?mails?|mail)(?:\s+in (?:Apple )?Mail)?[.!?]*$"#,
        ]
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            if let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
               let range = Range(match.range(at: 1), in: body) {
                let query = String(body[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { throw MailSearchError.invalidQuery }
                return try Self(query: query)
            }
        }
        throw MailSearchError.invalidQuery
    }
}

public enum MailSearchError: LocalizedError {
    case invalidQuery, unsupported
    public var errorDescription: String? {
        switch self {
        case .invalidQuery: "What should I search for? Try ‘Find the latest Draper email’."
        case .unsupported: "I can search Apple Mail. Try ‘Find emails about invoices’."
        }
    }
}
