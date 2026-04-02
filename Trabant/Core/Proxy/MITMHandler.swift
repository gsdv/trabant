import Foundation
import NIOCore
import NIOHTTP1

/// Handles HTTP traffic inside a decrypted HTTPS MITM tunnel.
/// After the TLS handshake with the client completes, this handler sees
/// cleartext HTTP and forwards it to the real upstream server over TLS.
final class MITMHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let host: String
    private let port: Int
    private let deviceIP: String
    private let onSessionCaptured: @Sendable (ProxySession) -> Void
    private let onSessionUpdated: @Sendable (ProxySession) -> Void

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?
    init(
        host: String,
        port: Int,
        deviceIP: String,
        onSessionCaptured: @escaping @Sendable (ProxySession) -> Void,
        onSessionUpdated: @escaping @Sendable (ProxySession) -> Void
    ) {
        self.host = host
        self.port = port
        self.deviceIP = deviceIP
        self.onSessionCaptured = onSessionCaptured
        self.onSessionUpdated = onSessionUpdated
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
        case .body(var buffer):
            requestBody?.writeBuffer(&buffer)
        case .end:
            if let head = requestHead {
                forwardToUpstream(context: context, head: head, body: requestBody)
            }
            requestHead = nil
            requestBody = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let description = String(describing: error)
        if description.contains("StreamClosed") && description.contains("Cancel") {
            ProxyLogger.debug("mitm stream cancelled host=\(host) error=\(description)")
            context.close(promise: nil)
            return
        }
        if description.contains("SSLV3_ALERT_CERTIFICATE_UNKNOWN") {
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
            ProxyLogger.error("client rejected mitm host=\(host) error=\(description)")
        } else {
            ProxyLogger.error("mitm stream error host=\(host) error=\(description)")
        }
        context.close(promise: nil)
    }

    private func forwardToUpstream(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        let path = head.uri.hasPrefix("/") ? head.uri : "/\(head.uri)"
        let requestTimestamp = Date()
        let normalizedProtocol = head.version.major == 2 ? "h2" : "http/1.1"
        let request = UpstreamRequest(
            sessionID: UUID(),
            deviceIP: deviceIP,
            scheme: "https",
            method: head.method.rawValue,
            host: host,
            port: port,
            path: path,
            url: "https://\(host)\(port == 443 ? "" : ":\(port)")\(path)",
            requestHeaders: head.headers.map { ($0.name, $0.value) },
            requestBody: body.flatMap { $0.readableBytes > 0 ? Data($0.readableBytesView) : nil },
            requestTimestamp: requestTimestamp,
            requestProtocol: normalizedProtocol,
            captureMode: .mitm,
            isDecrypted: true
        )
        ProxyLogger.debug("mitm forward session=\(request.sessionID) protocol=\(normalizedProtocol) url=\(request.url)")
        onSessionCaptured(request.pendingSession())
        UpstreamTransport.shared.execute(
            request: request,
            clientChannel: context.channel,
            onSessionUpdated: onSessionUpdated
        )
    }
}
