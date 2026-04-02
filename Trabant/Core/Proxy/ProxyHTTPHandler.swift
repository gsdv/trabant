import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOFoundationCompat

/// Handles each incoming proxy connection. Routes plain HTTP requests upstream
/// and upgrades CONNECT requests to TLS MITM interception.
final class ProxyHTTPHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let certificateAuthority: CertificateAuthority?
    private let onSessionCaptured: @Sendable (ProxySession) -> Void
    private let onSessionUpdated: @Sendable (ProxySession) -> Void

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?
    private var deviceIP: String?
    private var pendingCONNECTHost: String?
    private var pendingCONNECTPort: Int?

    init(
        certificateAuthority: CertificateAuthority?,
        onSessionCaptured: @escaping @Sendable (ProxySession) -> Void,
        onSessionUpdated: @escaping @Sendable (ProxySession) -> Void
    ) {
        self.certificateAuthority = certificateAuthority
        self.onSessionCaptured = onSessionCaptured
        self.onSessionUpdated = onSessionUpdated
    }

    func channelActive(context: ChannelHandlerContext) {
        // Capture the client IP for device grouping
        if let remote = context.remoteAddress {
            deviceIP = remote.ipAddress
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            if head.method == .CONNECT {
                handleCONNECT(context: context, head: head)
            } else {
                requestHead = head
                requestBody = context.channel.allocator.buffer(capacity: 0)
            }
        case .body(var buffer):
            requestBody?.writeBuffer(&buffer)
        case .end:
            if pendingCONNECTHost != nil {
                // CONNECT .end — pipeline upgrade is triggered by the flush callback
                // in handleCONNECT, not here.
            } else if let head = requestHead {
                forwardHTTPRequest(context: context, head: head, body: requestBody)
            }
            requestHead = nil
            requestBody = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ProxyLogger.error("client connection error device=\(deviceIP ?? "unknown") error=\(String(describing: error))")
        context.close(promise: nil)
    }

    // MARK: - Plain HTTP Forwarding

    private func forwardHTTPRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        guard let url = resolvedHTTPURL(for: head) else {
            sendError(context: context, status: .badRequest, message: "Invalid URL")
            return
        }

        let host = url.host ?? head.headers["host"].first ?? ""
        let port = url.port ?? 80
        let path: String = {
            var p = url.path.isEmpty ? "/" : url.path
            if let q = url.query { p += "?\(q)" }
            return p
        }()

        // Rewrite request to use relative URI for upstream
        let requestTimestamp = Date()
        let clientIP = deviceIP ?? "unknown"
        let urlString = buildURLString(scheme: "http", host: host, port: port, path: path)
        let request = UpstreamRequest(
            sessionID: UUID(),
            deviceIP: clientIP,
            scheme: "http",
            method: head.method.rawValue,
            host: host,
            port: port,
            path: path,
            url: urlString,
            requestHeaders: head.headers.map { ($0.name, $0.value) },
            requestBody: body.flatMap { $0.readableBytes > 0 ? Data($0.readableBytesView) : nil },
            requestTimestamp: requestTimestamp,
            requestProtocol: "http/1.1",
            captureMode: .mitm,
            isDecrypted: true
        )
        ProxyLogger.debug("forward http session=\(request.sessionID) url=\(request.url)")
        onSessionCaptured(request.pendingSession())
        UpstreamTransport.shared.execute(
            request: request,
            clientChannel: context.channel,
            onSessionUpdated: onSessionUpdated
        )
    }

    // MARK: - CONNECT / HTTPS MITM

    private func handleCONNECT(context: ChannelHandlerContext, head: HTTPRequestHead) {
        // Parse host:port from CONNECT target (e.g. "example.com:443")
        let parts = head.uri.split(separator: ":")
        let host = String(parts[0])
        let port = parts.count > 1 ? Int(parts[1]) ?? 443 : 443
        ProxyLogger.debug("connect request host=\(host) port=\(port) device=\(deviceIP ?? "unknown")")

        // Flag so .end is a no-op
        pendingCONNECTHost = host
        pendingCONNECTPort = port

        // If this domain previously failed MITM (e.g. certificate pinning via Cronet),
        // use a transparent TCP tunnel so the app can still reach the real server.
        if BypassDomains.shared.contains(host) {
            tunnelCONNECT(
                context: context,
                host: host,
                port: port,
                reason: "Client previously rejected the MITM certificate for this host. Using a raw CONNECT tunnel."
            )
            return
        }

        guard let ca = certificateAuthority, ca.isReady else {
            sendError(context: context, status: .serviceUnavailable, message: "HTTPS interception not available (no CA)")
            return
        }

        // Send 200 Connection Established, then upgrade AFTER it's flushed to the socket.
        // IMPORTANT: Do NOT send .end(nil) — NIOHTTP1's encoder emits chunked transfer-
        // encoding terminator bytes (0\r\n\r\n) which leak into the tunnel as garbage,
        // causing the client's TLS to fail (apple/swift-nio-ssl#539).
        var response = HTTPResponseHead(version: .http1_1, status: .ok)
        response.headers.add(name: "Content-Length", value: "0")
        let flushPromise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(wrapOutboundOut(.head(response)), promise: flushPromise)

        flushPromise.futureResult.whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.upgradeToPipeline(context: context, host: host, port: port, ca: ca)
            case .failure:
                context.channel.close(promise: nil)
            }
        }
    }

    private func upgradeToPipeline(context: ChannelHandlerContext, host: String, port: Int, ca: CertificateAuthority) {
        do {
            let (chain, key) = try ca.leafCertificate(for: host)
            var tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: chain.map { .certificate($0) },
                privateKey: .privateKey(key)
            )
            tlsConfig.applicationProtocols = ProxyTLSSettings.mitmApplicationProtocols
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            let channel = context.channel
            let pipeline = channel.pipeline

            // Remove old handlers, then add MITM pipeline.
            // The 200 response has already been flushed to the socket.
            pipeline.removeHandler(name: "proxy-handler").flatMap {
                pipeline.removeHandler(name: "http-encoder")
            }.flatMap {
                pipeline.removeHandler(name: "http-decoder")
            }.flatMap {
                pipeline.addHandler(sslHandler, name: "ssl-server")
            }.flatMap {
                pipeline.addHandler(
                    MITMTLSFailureHandler(
                        host: host,
                        port: port,
                        deviceIP: self.deviceIP ?? "unknown",
                        onSessionCaptured: self.onSessionCaptured
                    ),
                    name: "mitm-tls-monitor"
                )
            }.flatMap {
                channel.configureCommonHTTPServerPipeline { requestChannel in
                    let mitmHandler = MITMHandler(
                        host: host,
                        port: port,
                        deviceIP: self.deviceIP ?? "unknown",
                        onSessionCaptured: self.onSessionCaptured,
                        onSessionUpdated: self.onSessionUpdated
                    )
                    return requestChannel.pipeline.addHandler(mitmHandler)
                }
            }.whenFailure { error in
                let failure = ProxyFailureClassifier.unsupportedDownstreamProtocol(error)
                ProxyLogger.error("mitm pipeline failure host=\(host) kind=\(failure.kind.rawValue) error=\(failure.message)")
                channel.close(promise: nil)
            }
        } catch {
            ProxyLogger.error("mitm certificate setup failure host=\(host) error=\(String(describing: error))")
            context.channel.close(promise: nil)
        }
    }

    // MARK: - Transparent CONNECT Tunnel

    /// Establishes a transparent TCP tunnel for CONNECT requests where MITM is not possible
    /// (e.g. the client uses certificate pinning). Sends 200, then pipes raw bytes bidirectionally
    /// between the client and the real upstream without TLS interception.
    private func tunnelCONNECT(context: ChannelHandlerContext, host: String, port: Int, reason: String) {
        let sessionID = UUID()
        let requestTimestamp = Date()
        var tunnelSession = ProxySession(
            id: sessionID,
            deviceIP: deviceIP ?? "unknown",
            scheme: "https",
            method: "CONNECT",
            host: host,
            port: port,
            path: "/",
            url: buildURLString(scheme: "https", host: host, port: port, path: "/"),
            requestHeaders: [],
            requestBody: nil,
            responseStatusCode: nil,
            responseHeaders: [],
            responseBody: nil,
            requestTimestamp: requestTimestamp,
            responseTimestamp: requestTimestamp,
            error: nil,
            requestProtocol: "tunnel",
            upstreamProtocol: nil,
            captureMode: .tunnel,
            failureReason: reason,
            isDecrypted: false
        )
        onSessionCaptured(tunnelSession)

        var response = HTTPResponseHead(version: .http1_1, status: .ok)
        response.headers.add(name: "Content-Length", value: "0")
        let flushPromise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(wrapOutboundOut(.head(response)), promise: flushPromise)

        flushPromise.futureResult.whenComplete { result in
            guard case .success = result else {
                context.channel.close(promise: nil)
                return
            }
            let clientRelay = TunnelRelayHandler()
            let upstreamRelay = TunnelRelayHandler()
            let pipeline = context.channel.pipeline

            pipeline.removeHandler(name: "proxy-handler").flatMap {
                pipeline.removeHandler(name: "http-encoder")
            }.flatMap {
                pipeline.addHandler(clientRelay, name: "tunnel-relay")
            }.flatMap {
                pipeline.removeHandler(name: "http-decoder")
            }.whenComplete { pipelineResult in
                switch pipelineResult {
                case .success:
                    ClientBootstrap(group: context.eventLoop)
                        .channelOption(.allowRemoteHalfClosure, value: true)
                        .channelInitializer { channel in
                            channel.pipeline.addHandler(upstreamRelay)
                        }
                        .connectTimeout(.seconds(10))
                        .connect(host: host, port: port)
                        .whenComplete { connectResult in
                            switch connectResult {
                            case .success(let upstream):
                                clientRelay.attachPeer(upstream)
                                upstreamRelay.attachPeer(context.channel)
                                tunnelSession.responseStatusCode = 200
                                tunnelSession.responseTimestamp = Date()
                                self.onSessionUpdated(tunnelSession)
                                ProxyLogger.info("tunnel established host=\(host) port=\(port)")
                            case .failure(let error):
                                let failure = ProxyFailureClassifier.classifyUpstream(error)
                                tunnelSession.error = failure.displayText
                                tunnelSession.failureReason = failure.displayText
                                tunnelSession.responseTimestamp = Date()
                                self.onSessionUpdated(tunnelSession)
                                context.channel.close(promise: nil)
                            }
                        }
                case .failure:
                    context.channel.close(promise: nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sendError(context: ChannelHandlerContext, status: HTTPResponseStatus, message: String) {
        ProxyLogger.error("proxy error status=\(status.code) message=\(message)")
        let body = message.data(using: .utf8) ?? Data()
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        headers.add(name: "Content-Length", value: "\(body.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func resolvedHTTPURL(for head: HTTPRequestHead) -> URL? {
        if let url = URL(string: head.uri), url.scheme != nil {
            return url
        }

        guard let hostHeader = head.headers["host"].first else { return nil }
        let path = head.uri.hasPrefix("/") ? head.uri : "/\(head.uri)"
        return URL(string: "http://\(hostHeader)\(path)")
    }

    private func buildURLString(scheme: String, host: String, port: Int, path: String) -> String {
        let isDefaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        let portSuffix = isDefaultPort ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portSuffix)\(path)"
    }
}
