import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

/// Tiny HTTP server on port 9091 that serves the CA certificate for iPhone installation.
final class CertificateFileServer: @unchecked Sendable {
    private let certificateAuthority: CertificateAuthority
    private var channel: Channel?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    init(certificateAuthority: CertificateAuthority) {
        self.certificateAuthority = certificateAuthority
    }

    func start(port: Int) async throws {
        let ca = certificateAuthority
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(HTTPRequestDecoder()),
                    HTTPResponseEncoder(),
                    CertFileHandler(certificateAuthority: ca)
                ])
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 1)

        channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
    }

    func stop() async throws {
        try await channel?.close()
        try await group.shutdownGracefully()
    }
}

private final class CertFileHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let certificateAuthority: CertificateAuthority

    init(certificateAuthority: CertificateAuthority) {
        self.certificateAuthority = certificateAuthority
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .head(let head) = part else { return }

        if head.uri == "/trabant-ca.cer" || head.uri == "/" {
            serveCertificate(context: context, isDownload: head.uri.hasSuffix(".cer"))
        } else {
            serveNotFound(context: context)
        }
    }

    private func serveCertificate(context: ChannelHandlerContext, isDownload: Bool) {
        if isDownload {
            // Serve the DER certificate
            guard let data = try? certificateAuthority.exportedCertData() else {
                serveError(context: context, message: "CA not generated yet")
                return
            }
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/x-x509-ca-cert")
            headers.add(name: "Content-Length", value: "\(data.count)")

            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        } else {
            // Serve a simple HTML page with download link
            let html = """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
            <title>Trabant CA</title>
            <style>body{font-family:-apple-system,sans-serif;max-width:400px;margin:40px auto;padding:20px;background:#1a1a2e;color:#e0e0e0;}
            a{color:#7c5cbf;font-size:18px;display:block;margin:20px 0;padding:12px;background:#2a2a4a;border-radius:8px;text-align:center;text-decoration:none;}
            </style></head><body>
            <h2>Trabant CA Certificate</h2>
            <a href="/trabant-ca.cer">Download Certificate</a>
            <p style="font-size:13px;color:#888;">After downloading, go to Settings → General → About → Certificate Trust Settings and enable full trust for Trabant CA.</p>
            </body></html>
            """
            let data = Data(html.utf8)
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/html; charset=utf-8")
            headers.add(name: "Content-Length", value: "\(data.count)")

            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(wrapOutboundOut(.head(head)), promise: nil)

            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }

    private func serveNotFound(context: ChannelHandlerContext) {
        let head = HTTPResponseHead(version: .http1_1, status: .notFound)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func serveError(context: ChannelHandlerContext, message: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain")
        let head = HTTPResponseHead(version: .http1_1, status: .internalServerError, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
