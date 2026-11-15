import Foundation

/// The boundary between interpreting an instruction and acting on the computer.
public enum Action: Equatable, Sendable {
    case openURL(URL)
    case openApplication(String)
    case searchWeb(String)

    public var label: String {
        switch self {
        case .openURL(let url): "Opening \(url.host ?? url.absoluteString)…"
        case .openApplication(let name): "Opening \(name)…"
        case .searchWeb(let query): "Searching for \(query)…"
        }
    }

    public var webURL: URL? {
        switch self {
        case .openURL(let url): return url
        case .openApplication: return nil
        case .searchWeb(let query):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            // Search servers interpret a literal plus as a form-encoded space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return components.url
        }
    }
}

public enum InstructionError: LocalizedError, Equatable {
    case empty
    case unsupported
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .empty: "Type an instruction first."
        case .unsupported: "Try ‘Open Safari’, ‘Open github.com’, or ‘Search for coffee nearby’."
        case .invalidURL: "Enter a valid http or https address."
        }
    }
}

/// An explicit first set of commands. Unsupported requests never fall through to a shell.
public struct InstructionParser: Sendable {
    public init() {}

    public func parse(_ input: String) throws -> Action {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InstructionError.empty }

        for prefix in ["search the web for ", "search for ", "search ", "google "] {
            if let query = remainder(of: text, after: prefix), !query.isEmpty {
                return .searchWeb(query)
            }
        }

        for prefix in ["open ", "launch ", "go to "] {
            if let target = remainder(of: text, after: prefix), !target.isEmpty {
                if target.contains(":") || target.contains(".") || target.contains("/") {
                    return .openURL(try parseURL(target))
                }
                guard prefix != "go to " else { throw InstructionError.invalidURL }
                return .openApplication(target)
            }
        }

        if text.contains("://") || (!text.contains(where: \.isWhitespace) && text.contains(".")) {
            return .openURL(try parseURL(text))
        }
        throw InstructionError.unsupported
    }

    private func remainder(of text: String, after prefix: String) -> String? {
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseURL(_ text: String) throws -> URL {
        guard !text.contains(where: \.isWhitespace) else { throw InstructionError.invalidURL }
        let address = text.contains("://") ? text : "https://\(text)"
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              host == "localhost" || host.contains("."),
              components.user == nil, components.password == nil,
              let url = components.url
        else { throw InstructionError.invalidURL }
        return url
    }
}
