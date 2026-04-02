import Foundation
import NIOCore
import NIOHTTP1
import NIOSSL
import NIOFoundationCompat

/// Relays upstream HTTP responses back to the client channel and captures
/// the completed request/response as a ProxySession.
/// Used by both HTTP proxy and HTTPS MITM handlers.
final class UpstreamResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let clientChannel: Channel
    private let sessionID: UUID
    private let scheme: String
    private let host: String
    private let requestHead: HTTPRequestHead
    private let requestBody: ByteBuffer?
    private let requestTimestamp: Date
    private let originalRequestHeaders: [(String, String)]
    private let originalRequestBody: Data?
    private let deviceIP: String
    private let onSessionCompleted: @Sendable (ProxySession) -> Void

    private var responseHead: HTTPResponseHead?
    private var responseBody: ByteBuffer
    private var responseComplete = false
    private let maxBodyCapture = 5 * 1024 * 1024 // 5 MB

    init(
        clientChannel: Channel,
        sessionID: UUID,
        scheme: String,
        host: String,
        requestHead: HTTPRequestHead,
        requestBody: ByteBuffer?,
        requestTimestamp: Date,
        originalRequestHeaders: [(String, String)],
        originalRequestBody: Data?,
        deviceIP: String,
        onSessionCompleted: @escaping @Sendable (ProxySession) -> Void
    ) {
        self.clientChannel = clientChannel
        self.sessionID = sessionID
        self.scheme = scheme
        self.host = host
        self.requestHead = requestHead
        self.requestBody = requestBody
        self.requestTimestamp = requestTimestamp
        self.originalRequestHeaders = originalRequestHeaders
        self.originalRequestBody = originalRequestBody
        self.deviceIP = deviceIP
        self.onSessionCompleted = onSessionCompleted
        self.responseBody = ByteBuffer()
    }

    func channelActive(context: ChannelHandlerContext) {
        // Send the request to upstream
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        if let body = requestBody, body.readableBytes > 0 {
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            responseHead = head
            // Forward to client
            clientChannel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        case .body(var buffer):
            // Capture body up to limit
            if responseBody.readableBytes < maxBodyCapture {
                let remaining = maxBodyCapture - responseBody.readableBytes
                let toCopy = min(remaining, buffer.readableBytes)
                if toCopy > 0, let slice = buffer.getSlice(at: buffer.readerIndex, length: toCopy) {
                    responseBody.writeImmutableBuffer(slice)
                }
            }
            // Always forward full body to client
            clientChannel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)

        case .end(let trailers):
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(trailers)), promise: nil)
            captureSession()
            responseComplete = true
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // After a complete response, ignore post-response errors like unclean TLS shutdown
        // (very common — most HTTP servers close without sending TLS close_notify)
        guard !responseComplete else {
            context.close(promise: nil)
            return
        }

        // If we got a partial response and the server just closed without close_notify,
        // complete with what we have rather than reporting an error
        if let sslError = error as? NIOSSLError, sslError == .uncleanShutdown, responseHead != nil {
            clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            captureSession()
            responseComplete = true
            context.close(promise: nil)
            return
        }

        // Report genuine errors
        print("[Trabant] Upstream error for \(host): \(error)")
        let path = requestHead.uri
        let session = ProxySession(
            id: sessionID,
            deviceIP: deviceIP,
            scheme: scheme,
            method: requestHead.method.rawValue,
            host: host,
            port: scheme == "https" ? 443 : 80,
            path: path,
            url: "\(scheme)://\(host)\(path)",
            requestHeaders: originalRequestHeaders,
            requestBody: originalRequestBody,
            responseStatusCode: nil,
            responseHeaders: [],
            responseBody: nil,
            requestTimestamp: requestTimestamp,
            responseTimestamp: Date(),
            error: error.localizedDescription,
            requestProtocol: "http/1.1",
            upstreamProtocol: "http/1.1",
            captureMode: .mitm,
            failureReason: error.localizedDescription,
            isDecrypted: true
        )
        onSessionCompleted(session)
        context.close(promise: nil)
    }

    private func captureSession() {
        guard let head = responseHead else { return }
        let path = requestHead.uri

        let respBodyData: Data? = responseBody.readableBytes > 0
            ? Data(responseBody.readableBytesView)
            : nil

        let session = ProxySession(
            id: sessionID,
            deviceIP: deviceIP,
            scheme: scheme,
            method: requestHead.method.rawValue,
            host: host,
            port: scheme == "https" ? 443 : 80,
            path: path,
            url: "\(scheme)://\(host)\(path)",
            requestHeaders: originalRequestHeaders,
            requestBody: originalRequestBody,
            responseStatusCode: Int(head.status.code),
            responseHeaders: head.headers.map { ($0.name, $0.value) },
            responseBody: respBodyData,
            requestTimestamp: requestTimestamp,
            responseTimestamp: Date(),
            error: nil,
            requestProtocol: "http/1.1",
            upstreamProtocol: "http/1.1",
            captureMode: .mitm,
            failureReason: nil,
            isDecrypted: true
        )
        onSessionCompleted(session)
    }
}
