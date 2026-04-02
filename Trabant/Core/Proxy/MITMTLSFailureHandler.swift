import Foundation
import NIOCore

/// Observes the TLS handshake on a CONNECT-upgraded channel.
/// If the client rejects the generated certificate, mark the host for future tunneling.
final class MITMTLSFailureHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let host: String
    private let port: Int
    private let deviceIP: String
    private let onSessionCaptured: @Sendable (ProxySession) -> Void
    private var sawApplicationData = false

    init(
        host: String,
        port: Int,
        deviceIP: String,
        onSessionCaptured: @escaping @Sendable (ProxySession) -> Void
    ) {
        self.host = host
        self.port = port
        self.deviceIP = deviceIP
        self.onSessionCaptured = onSessionCaptured
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        if buffer.readableBytes > 0 {
            sawApplicationData = true
        }
        context.fireChannelRead(data)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let description = String(describing: error)
        if Self.shouldBypassHost(for: description, sawApplicationData: sawApplicationData) {
            BypassDomains.shared.add(host)
            let failure = ProxyFailureClassifier.clientRejectedMITM(host: host, error: error)
            let session = ProxySession(
                id: UUID(),
                deviceIP: deviceIP,
                scheme: "https",
                method: "CONNECT",
                host: host,
                port: port,
                path: "/",
                url: "https://\(host)\(port == 443 ? "" : ":\(port)")/",
                requestHeaders: [],
                requestBody: nil,
                responseStatusCode: nil,
                responseHeaders: [],
                responseBody: nil,
                requestTimestamp: Date(),
                responseTimestamp: Date(),
                error: nil,
                requestProtocol: "tunnel",
                upstreamProtocol: nil,
                captureMode: .tunnel,
                failureReason: failure.displayText,
                isDecrypted: false
            )
            onSessionCaptured(session)
            ProxyLogger.error("client rejected mitm during handshake host=\(host) error=\(description)")
            context.close(promise: nil)
            return
        }

        if Self.isBenignHandshakeClosure(description) {
            ProxyLogger.debug("mitm handshake closed host=\(host) error=\(description)")
            context.close(promise: nil)
            return
        }

        ProxyLogger.error("mitm handshake error host=\(host) error=\(description)")
        context.fireErrorCaught(error)
    }

    static func shouldBypassHost(for description: String, sawApplicationData: Bool) -> Bool {
        isClientRejectedMITMError(description) || isLikelyClientHandshakeAbort(description, sawApplicationData: sawApplicationData)
    }

    private static func isClientRejectedMITMError(_ description: String) -> Bool {
        let normalized = description.lowercased()
        return normalized.contains("certificate_unknown")
            || normalized.contains("alert certificate unknown")
            || normalized.contains("unknown_ca")
            || normalized.contains("alert unknown ca")
            || normalized.contains("certificateverifyfailed")
    }

    private static func isLikelyClientHandshakeAbort(_ description: String, sawApplicationData: Bool) -> Bool {
        guard !sawApplicationData else { return false }
        let normalized = description.lowercased()
        return normalized.contains("eof during handshake")
            || normalized.contains("connection reset by peer")
    }

    private static func isBenignHandshakeClosure(_ description: String) -> Bool {
        let normalized = description.lowercased()
        return normalized.contains("uncleanshutdown")
    }
}
