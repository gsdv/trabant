import Foundation

enum UserAgentDeviceParser {

    struct DeviceInfo: Sendable {
        let type: String      // "iPhone", "iPad", "iPod", "Mac", "Apple Watch"
        let osVersion: String? // "18.4", "17.2", etc.

        var displayName: String {
            if let osVersion {
                return "\(type) (iOS \(osVersion))"
            }
            return type
        }
    }

    /// Parses an iOS/macOS User-Agent string and extracts device type + OS version.
    ///
    /// Handles common formats:
    /// - Safari/WebKit: `Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) ...`
    /// - CFNetwork:     `AppName/1.0 CFNetwork/1568.100.1 Darwin/24.0.0`
    /// - App-specific:  `TwitteriOS/10.x (iPhone15,3; OS 18.4; ...)`
    static func parse(_ userAgent: String) -> DeviceInfo? {
        let ua = userAgent

        // Detect device type
        let type: String
        if ua.contains("iPhone") {
            type = "iPhone"
        } else if ua.contains("iPad") {
            type = "iPad"
        } else if ua.contains("iPod") {
            type = "iPod"
        } else if ua.contains("Watch") || ua.contains("watchOS") {
            type = "Apple Watch"
        } else if ua.contains("Macintosh") || ua.contains("Mac OS X") {
            type = "Mac"
        } else {
            return nil
        }

        // Extract iOS version from various patterns
        let osVersion = parseOSVersion(from: ua)

        return DeviceInfo(type: type, osVersion: osVersion)
    }

    private static func parseOSVersion(from ua: String) -> String? {
        // Pattern: "CPU iPhone OS 18_4 like Mac OS X" or "CPU OS 18_4 like Mac OS X" (iPad)
        if let match = ua.range(of: #"CPU (?:iPhone )?OS (\d+[_\.]\d+(?:[_\.]\d+)?)"#, options: .regularExpression) {
            let segment = String(ua[match])
            return extractVersion(from: segment)
        }

        // Pattern: "OS 18.4;" (compact app-specific UAs)
        if let match = ua.range(of: #"; OS (\d+\.\d+)"#, options: .regularExpression) {
            let segment = String(ua[match])
            return extractVersion(from: segment)
        }

        // Pattern: "iOS/18.4" or "iOS 18.4"
        if let match = ua.range(of: #"iOS[/ ](\d+\.\d+)"#, options: .regularExpression) {
            let segment = String(ua[match])
            return extractVersion(from: segment)
        }

        return nil
    }

    private static func extractVersion(from segment: String) -> String? {
        // Pull out the version number (digits, dots, underscores)
        guard let match = segment.range(of: #"\d+[_\.]\d+(?:[_\.]\d+)?"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(segment[match])
        let version = raw.replacingOccurrences(of: "_", with: ".")

        // Strip trailing ".0" for cleanliness: "18.4.0" → "18.4"
        if version.hasSuffix(".0"), version.filter({ $0 == "." }).count == 2 {
            return String(version.dropLast(2))
        }
        return version
    }
}
