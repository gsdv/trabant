import Foundation

enum Redactor {

    // MARK: - Header redaction

    private static let redactedHeaderNames: Set<String> = [
        "authorization", "proxy-authorization",
        "cookie", "set-cookie",
        "x-api-key", "apikey", "x-token",
        "x-access-token", "x-refresh-token",
        "x-csrf-token", "x-xsrf-token",
    ]

    private static let ipHeaderNames: Set<String> = [
        "x-forwarded-for", "x-real-ip",
    ]

    static func redactHeaders(_ headers: [(String, String)]) -> [(String, String)] {
        headers.map { name, value in
            let lower = name.lowercased()
            if redactedHeaderNames.contains(lower) {
                return (name, redactAuthValue(name: lower, value: value))
            }
            if ipHeaderNames.contains(lower) {
                return (name, redactIP(value.trimmingCharacters(in: .whitespaces)))
            }
            return (name, value)
        }
    }

    private static func redactAuthValue(name: String, value: String) -> String {
        if name == "authorization" || name == "proxy-authorization",
           let space = value.firstIndex(of: " ") {
            return String(value[...space]) + "••••••••••••••••"
        }
        return "••••••••••••••••"
    }

    // MARK: - Body / free-text redaction

    static func redactBodyText(_ text: String) -> String {
        var result = text
        result = redactJWTs(in: result)
        result = redactEmails(in: result)
        result = redactUUIDs(in: result)
        result = redactIPs(in: result)
        result = redactLongHex(in: result)
        result = redactLongQuotedTokens(in: result)
        return result
    }

    // MARK: - IP redaction

    static func redactIP(_ ip: String) -> String {
        let parts = ip.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) && $0.count <= 3 })
        else { return ip }
        return "\(parts[0]).\(parts[1]).•.•"
    }

    static func redactIPsInText(_ text: String) -> String {
        redactIPs(in: text)
    }

    // MARK: - URL / path redaction

    static func redactURL(_ url: String) -> String {
        var result = redactUUIDs(in: url)
        result = redactIPs(in: result)
        guard let q = result.firstIndex(of: "?") else { return result }
        let base = String(result[..<q])
        let query = String(result[result.index(after: q)...])
        let redacted = query.split(separator: "&", omittingEmptySubsequences: false).map { param in
            let kv = param.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? "\(kv[0])=••••••" : String(param)
        }.joined(separator: "&")
        return "\(base)?\(redacted)"
    }

    // MARK: - Individual patterns

    private static func redactJWTs(in text: String) -> String {
        replace(#"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, in: text) { _ in
            "eyJ••••.••••.••••"
        }
    }

    private static func redactEmails(in text: String) -> String {
        replace(#"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, in: text) { match in
            guard let at = match.firstIndex(of: "@"),
                  let dot = match[match.index(after: at)...].lastIndex(of: ".") else {
                return "••••@••••"
            }
            return "••••@••••\(match[dot...])"
        }
    }

    private static func redactUUIDs(in text: String) -> String {
        replace(
            #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            in: text
        ) { _ in "••••••••-••••-••••-••••-••••••••••••" }
    }

    private static func redactIPs(in text: String) -> String {
        replace(#"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#, in: text) { match in
            redactIP(match)
        }
    }

    private static func redactLongHex(in text: String) -> String {
        replace(#"\b[0-9a-fA-F]{32,}\b"#, in: text) { match in
            String(match.prefix(4)) + "••••••••••••"
        }
    }

    private static func redactLongQuotedTokens(in text: String) -> String {
        replace(#"(?<=")[A-Za-z0-9+/=_.:-]{40,}(?=")"#, in: text) { match in
            String(match.prefix(4)) + "••••••••••••"
        }
    }

    // MARK: - Regex helper

    private static func replace(
        _ pattern: String,
        in text: String,
        using transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[cursor..<range.lowerBound]
            result += transform(String(text[range]))
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
