import Foundation

enum ProxyCaptureMode: String, Sendable {
    case mitm
    case tunnel

    var label: String { rawValue.uppercased() }
}

struct ProxySession: Identifiable, Sendable {
    let id: UUID
    let deviceIP: String
    let scheme: String
    let method: String
    let host: String
    let port: Int
    let path: String
    let url: String
    let requestHeaders: [(String, String)]
    let requestBody: Data?
    var responseStatusCode: Int?
    var responseHeaders: [(String, String)]
    var responseBody: Data?
    let requestTimestamp: Date
    var responseTimestamp: Date?
    var error: String?
    let requestProtocol: String
    var upstreamProtocol: String?
    let captureMode: ProxyCaptureMode
    var failureReason: String?
    let isDecrypted: Bool

    var durationMs: Double? {
        guard let end = responseTimestamp else { return nil }
        return end.timeIntervalSince(requestTimestamp) * 1000
    }

    var mimeType: String? {
        responseHeaders.first(where: { $0.0.lowercased() == "content-type" })?.1
    }

    var contentTypeShort: String {
        guard let mime = mimeType?.lowercased() else { return "" }
        if mime.contains("json") { return "JSON" }
        if mime.contains("html") { return "HTML" }
        if mime.contains("xml") { return "XML" }
        if mime.contains("javascript") { return "JS" }
        if mime.contains("css") { return "CSS" }
        if mime.contains("image") { return "IMG" }
        if mime.contains("text") { return "TXT" }
        if mime.contains("font") { return "FONT" }
        return ""
    }

    var isComplete: Bool {
        responseTimestamp != nil || responseStatusCode != nil || error != nil || failureReason != nil
    }

    var statusColor: String {
        guard let code = responseStatusCode else { return "gray" }
        switch code {
        case 200..<300: return "green"
        case 300..<400: return "blue"
        case 400..<500: return "orange"
        case 500..<600: return "red"
        default: return "gray"
        }
    }

    var requestProtocolBadge: String {
        switch requestProtocol.lowercased() {
        case "h2": return "H2"
        case "http/1.1": return "H1"
        default: return requestProtocol.uppercased()
        }
    }

    var isSuccessfulTunnel: Bool {
        captureMode == .tunnel && responseStatusCode == 200 && error == nil
    }

    var isTunnelLearningFailure: Bool {
        guard captureMode == .tunnel, responseStatusCode == nil else { return false }
        let text = [error, failureReason]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return text.contains("rejected the generated certificate") || text.contains("future requests will use a raw tunnel")
    }

    var isLowSignalMediaRequest: Bool {
        guard captureMode == .mitm,
              method == "GET",
              (responseStatusCode ?? 0) >= 200,
              (responseStatusCode ?? 0) < 300
        else {
            return false
        }

        let lowercasedPath = path.lowercased()
        if contentTypeShort == "IMG" {
            return true
        }

        let mediaMarkers = [
            "/profile_images/",
            "/profile_banners/",
            "/media/",
            ".m3u8",
            ".m4s",
            ".mp4",
        ]
        return mediaMarkers.contains { lowercasedPath.contains($0) }
    }
}

struct DisplayedProxySession: Identifiable, Sendable {
    let session: ProxySession
    var collapsedCount: Int
    var representedSessionIDs: Set<UUID>

    var id: UUID { session.id }

    init(session: ProxySession, collapsedCount: Int, representedSessionIDs: Set<UUID>? = nil) {
        self.session = session
        self.collapsedCount = collapsedCount
        self.representedSessionIDs = representedSessionIDs ?? [session.id]
    }
}
