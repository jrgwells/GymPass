import Foundation

/// Best-effort, centralised redaction for anything that may leave the process
/// (logs, diagnostic exports, error descriptions). Do not rely on individual
/// call sites remembering to redact.
public enum Redactor {
    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static let rules: [Rule] = {
        let raw: [(String, String)] = [
            (#"(?i)(authorization\s*[:=]\s*)([^\s,;]+)"#, "$1<redacted>"),
            (#"(?i)(applepass\s+)([A-Za-z0-9\-._~+/]+=*)"#, "$1<redacted>"),
            (#"(?i)(bearer\s+)([A-Za-z0-9\-._~+/]+=*)"#, "$1<redacted>"),
            (#"(?i)(x-gympass-control-token\s*[:=]\s*)([^\s,;]+)"#, "$1<redacted>"),
            (#"exerp:checkin:[A-Za-z0-9\-_.]+"#, "exerp:checkin:<redacted>"),
            (#"(?i)("pass(token|word)"|authenticationToken|refresh_token|access_token|pushToken|installToken|pin)"\s*[:=]\s*"?[^"\s,}]+"?"#, "$1=<redacted>"),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<redacted-email>"),
            (#"/install/[A-Za-z0-9\-_]{16,}"#, "/install/<redacted>"),
            (#"\b[0-9a-fA-F]{64}\b"#, "<redacted-hex>"),
            (#"\b[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\b"#, "<redacted-uuid>"),
        ]
        return raw.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Rule(regex: regex, template: template)
        }
    }()

    public static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }
        return result
    }

    /// Redacts a URL, removing query parameters and install tokens.
    public static func redact(url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems?.map { item -> URLQueryItem in
            let sensitive = ["token", "passesUpdatedSince", "authorization", "auth"].contains(item.name.lowercased())
            return URLQueryItem(name: item.name, value: sensitive ? "<redacted>" : item.value)
        }
        components?.queryItems = items
        let string = components?.url?.absoluteString ?? url.absoluteString
        return redact(string)
    }

    /// Produces a redacted JSON dictionary from an arbitrary encodable value.
    public static func redactedJSON(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return redact(text)
    }
}
