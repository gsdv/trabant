import NIOCore
import NIOHTTP1

/// Bidirectional raw-byte relay for transparent CONNECT tunneling.
/// Buffers early reads until the peer channel is attached, then forwards
/// raw bytes bidirectionally and propagates half-closures where possible.
final class TunnelRelayHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = Any

    private var peerChannel: Channel?
    private var context: ChannelHandlerContext?
    private var pendingBuffers: [ByteBuffer] = []
    private var isClosingPeer = false

    init(peerChannel: Channel? = nil) {
        self.peerChannel = peerChannel
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        if let peerChannel {
            flushPendingBuffers(to: peerChannel)
        }
    }

    func attachPeer(_ peerChannel: Channel) {
        if let context, !context.eventLoop.inEventLoop {
            context.eventLoop.execute {
                self.attachPeer(peerChannel)
            }
            return
        }

        self.peerChannel = peerChannel
        flushPendingBuffers(to: peerChannel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let inbound = Self.unwrapInboundIn(data)

        if let buffer = inbound as? ByteBuffer {
            forward(buffer)
            return
        }

        if let ioData = inbound as? IOData, case .byteBuffer(let buffer) = ioData {
            forward(buffer)
            return
        }

        if let part = inbound as? HTTPServerRequestPart {
            switch part {
            case .body(let buffer):
                forward(buffer)
            case .head, .end:
                break
            }
            return
        }

        context.fireChannelRead(data)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case ChannelEvent.inputClosed = event, let peerChannel {
            peerChannel.close(mode: .output, promise: nil)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        closePeer()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        closePeer()
        context.close(promise: nil)
    }

    private func forward(_ buffer: ByteBuffer) {
        guard let peerChannel else {
            pendingBuffers.append(buffer)
            return
        }

        peerChannel.writeAndFlush(NIOAny(buffer), promise: nil)
    }

    private func flushPendingBuffers(to peerChannel: Channel) {
        guard !pendingBuffers.isEmpty else { return }
        for buffer in pendingBuffers {
            peerChannel.write(NIOAny(buffer), promise: nil)
        }
        pendingBuffers.removeAll(keepingCapacity: false)
        peerChannel.flush()
    }

    private func closePeer() {
        guard !isClosingPeer else { return }
        isClosingPeer = true
        peerChannel?.close(promise: nil)
    }
}
