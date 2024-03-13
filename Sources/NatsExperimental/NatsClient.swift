import NIO
import Foundation
import NIOConcurrencyHelpers

public class NatsClient {
    private let group: EventLoopGroup
    private var bootstrap: ClientBootstrap?
    private let handler = NatsHandler()
    private var channel: Channel?

    public init(eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)) {
        self.group = eventLoopGroup
    }

    public func connect(host: String, port: Int) async throws {
        self.bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(NatsDecoder())).flatMap { _ in
                    channel.pipeline.addHandler(self.handler)
                }
            }
        
        guard let bootstrap = self.bootstrap else {
            throw NatsClientError.notConnected
        }
        
        let futureConnection = bootstrap.connect(host: host, port: port)
        let channel = try await withCheckedThrowingContinuation { continuation in
            futureConnection.whenSuccess { channel in
                // Create a promise to signal when the first message is received
                let firstMessagePromise = channel.eventLoop.makePromise(of: Void.self)
                
                // Store the promise and continuation in the channel's user data
                self.handler.data = NatsClientData(firstMessagePromise: firstMessagePromise, continuation: continuation)
            }
            futureConnection.whenFailure { error in
                continuation.resume(throwing: error)
            }
        }
        self.channel = channel
    }

    public func send(_ message: Data) async throws {
        guard let channel = channel else {
            throw NatsClientError.notConnected
        }
        var buffer = channel.allocator.buffer(capacity: message.count)
        buffer.writeBytes(message)
        try await channel.writeAndFlush(buffer).get()
    }

    public func ping() async throws -> Duration {
        let ping = PingCommand.makeFrom(channel: self.channel)
        self.handler.pingQueue.enqueue(ping)
        try await send("PING\r\n".data(using: .utf8)!)
        return try await ping.getRoundTripTime()
    }
    
    public func close() throws {
        if let channel = channel {
            try channel.close().wait()
            self.channel = nil
        }
        try group.syncShutdownGracefully()
    }
}

enum NatsClientError: Error {
    case notConnected
}

class NatsHandler: ChannelInboundHandler {
    typealias InboundIn = NatsMessage
    typealias OutboundOut = ByteBuffer
    
    var data: NatsClientData?
    let pingQueue = ConcurrentQueue<PingCommand>()

    func channelActive(context: ChannelHandlerContext) {
        print("Connected to NATS server")
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        switch message {
        case .info(let infoMessage):
            handleInfo(context, infoMessage)
        case .ping:
            handlePing(context: context)
        case .pong:
            handlePong(context: context)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }

    private func handleInfo(_ context: ChannelHandlerContext, _ message: String) {
        print("Received INFO message:")
        print(message)
        // Parse and handle the INFO message as needed
        if let data = self.data {
            data.continuation.resume(returning: context.channel)
        }
    }

    private func handlePing(context: ChannelHandlerContext) {
        print("Received PING message")
        // Respond with a PONG message
        sendPong(context: context)
    }
    
    private func handlePong(context: ChannelHandlerContext) {
        print("Received PONG message")
        self.pingQueue.dequeue()?.setRoundTripTime()
    }

    private func sendPong(context: ChannelHandlerContext) {
        let pongMessage = "PONG\r\n"
        var buffer = context.channel.allocator.buffer(capacity: pongMessage.count)
        buffer.writeString(pongMessage)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
}

class NatsDecoder: ByteToMessageDecoder {
    typealias InboundOut = NatsMessage

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let readableBytes = buffer.readableBytesView.firstIndex(of: 10) else {
            return .needMoreData
        }

        let length = readableBytes + 1
        guard let message = buffer.readString(length: length) else {
            return .needMoreData
        }

        //buffer.moveReaderIndex(forwardBy: 2) // Move past the '\r\n'

        if message.starts(with: "INFO") {
            context.fireChannelRead(wrapInboundOut(NatsMessage.info(message)))
            return .continue
        } else if message.starts(with: "PING") {
            context.fireChannelRead(wrapInboundOut(NatsMessage.ping))
            return .continue
        } else if message.starts(with: "PONG") {
            context.fireChannelRead(wrapInboundOut(NatsMessage.pong))
            return .continue
        } else {            // Handle other NATS protocol messages
            return .needMoreData
        }
    }
}

enum NatsMessage {
    case info(String)
    case ping
    case pong
    // Add other NATS protocol message cases as needed
}

struct NatsClientData {
    let firstMessagePromise: EventLoopPromise<Void>
    let continuation: CheckedContinuation<Channel, Error>
}

class ConcurrentQueue<T> {
    private var elements: [T] = []
    private let lock = NIOLock()

    func enqueue(_ element: T) {
        lock.lock()
        defer { lock.unlock() }
        elements.append(element)
    }

    func dequeue() -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }
}

class PingCommand {
    let startTime = ContinuousClock().now
    let promise: EventLoopPromise<Duration>?

    static func makeFrom(channel: Channel?) -> PingCommand {
        PingCommand(promise: channel?.eventLoop.makePromise(of: Duration.self))
    }

    private init(promise: EventLoopPromise<Duration>?) {
        self.promise = promise
    }

    func setRoundTripTime() {
        let now: ContinuousClock.Instant = ContinuousClock().now
        let rtt: Duration = now - startTime
        promise?.succeed(rtt)
    }

    func getRoundTripTime() async throws -> Duration {
        try await promise?.futureResult.get() ?? Duration.zero
    }
}

