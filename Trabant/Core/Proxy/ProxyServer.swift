import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

/// The main proxy server that accepts connections from devices and dispatches to HTTP/HTTPS handlers.
final class ProxyServer: @unchecked Sendable {
    private let certificateAuthority: CertificateAuthority?
    private let onSessionCaptured: @Sendable (ProxySession) -> Void
    private let onSessionUpdated: @Sendable (ProxySession) -> Void
    private var channel: Channel?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    init(
        certificateAuthority: CertificateAuthority?,
        onSessionCaptured: @escaping @Sendable (ProxySession) -> Void,
        onSessionUpdated: @escaping @Sendable (ProxySession) -> Void
    ) {
        self.certificateAuthority = certificateAuthority
        self.onSessionCaptured = onSessionCaptured
        self.onSessionUpdated = onSessionUpdated
    }

    func start(port: Int) async throws {
        let ca = certificateAuthority
        let captured = onSessionCaptured
        let updated = onSessionUpdated

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let handler = ProxyHTTPHandler(
                    certificateAuthority: ca,
                    onSessionCaptured: captured,
                    onSessionUpdated: updated
                )
                return channel.pipeline.addHandler(
                    ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)),
                    name: "http-decoder"
                ).flatMap {
                    channel.pipeline.addHandler(HTTPResponseEncoder(), name: "http-encoder")
                }.flatMap {
                    channel.pipeline.addHandler(handler, name: "proxy-handler")
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelOption(.allowRemoteHalfClosure, value: true)

        channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
    }

    func stop() async throws {
        try await channel?.close()
        try await group.shutdownGracefully()
    }
}
