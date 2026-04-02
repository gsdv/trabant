import Foundation

struct UpstreamRequest: Sendable {
    let sessionID: UUID
    let deviceIP: String
    let scheme: String
    let method: String
    let host: String
    let port: Int
    let path: String
    let url: String
    let requestHeaders: [(String, String)]
    let requestBody: Data?
    let requestTimestamp: Date
    let requestProtocol: String
    let captureMode: ProxyCaptureMode
    let isDecrypted: Bool

    var urlObject: URL? {
        URL(string: url)
    }

    func pendingSession() -> ProxySession {
        ProxySession(
            id: sessionID,
            deviceIP: deviceIP,
            scheme: scheme,
            method: method,
            host: host,
            port: port,
            path: path,
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: nil,
            responseHeaders: [],
            responseBody: nil,
            requestTimestamp: requestTimestamp,
            responseTimestamp: nil,
            error: nil,
            requestProtocol: requestProtocol,
            upstreamProtocol: nil,
            captureMode: captureMode,
            failureReason: nil,
            isDecrypted: isDecrypted
        )
    }

    func completedSession(
        responseStatusCode: Int?,
        responseHeaders: [(String, String)],
        responseBody: Data?,
        responseTimestamp: Date,
        upstreamProtocol: String?,
        error: String? = nil,
        failureReason: String? = nil
    ) -> ProxySession {
        ProxySession(
            id: sessionID,
            deviceIP: deviceIP,
            scheme: scheme,
            method: method,
            host: host,
            port: port,
            path: path,
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: responseStatusCode,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            requestTimestamp: requestTimestamp,
            responseTimestamp: responseTimestamp,
            error: error,
            requestProtocol: requestProtocol,
            upstreamProtocol: upstreamProtocol,
            captureMode: captureMode,
            failureReason: failureReason,
            isDecrypted: isDecrypted
        )
    }

    func failedSession(_ failure: ProxyFailure, responseTimestamp: Date = Date()) -> ProxySession {
        completedSession(
            responseStatusCode: nil,
            responseHeaders: [],
            responseBody: nil,
            responseTimestamp: responseTimestamp,
            upstreamProtocol: nil,
            error: failure.displayText,
            failureReason: failure.displayText
        )
    }
}
