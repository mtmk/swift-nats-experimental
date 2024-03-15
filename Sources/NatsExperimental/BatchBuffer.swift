import Foundation
import NIO
import NIOConcurrencyHelpers

class BatchBuffer {
    private let batchSize: Int
    private var buffer: ByteBuffer
    private let channel: Channel
    private let lock = NIOLock()
    private var waitingPromises: [EventLoopPromise<Void>] = []
    private var isWriteInProgress: Bool = false

    init(channel: Channel, batchSize: Int = 16*1024) {
        self.batchSize = batchSize
        self.buffer = channel.allocator.buffer(capacity: batchSize)
        self.channel = channel
    }
    
    func write(data: Data) async throws {
        // Batch writes and if we have more than the batch size
        // already in the buffer await until buffer is flushed
        // to handle any back pressure
        try await withCheckedThrowingContinuation { continuation in
            self.lock.withLock {
                guard self.buffer.readableBytes < self.batchSize else {
                    let promise = self.channel.eventLoop.makePromise(of: Void.self)
                    promise.futureResult.whenComplete { result in
                        switch result {
                        case .success:
                            _ = self.lock.withLock {
                                self.buffer.writeBytes(data)
                            }
                            self.flushWhenIdle()
                            continuation.resume()
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    waitingPromises.append(promise)
                    return
                }

                self.buffer.writeBytes(data)
                continuation.resume()
            }
            
            flushWhenIdle()
        }
    }
    
    func clear() {
        lock.withLock {
            self.buffer.clear()
        }
    }
    
    private func flushWhenIdle() {
        Task.detached {
            
            self.lock.lock()

            // The idea is to keep writing to the buffer while a
            // writeAndFlush() is in progress, so we can batch as
            // many messages as possible.
            guard !self.isWriteInProgress else {
                self.lock.unlock()
                return
            }
            
            // We need a separate write buffer so we can free the
            // message buffer for more messages to be collected.
            guard let writeBuffer = self.getWriteBuffer() else {
                self.lock.unlock()
                return
            }
            
            self.isWriteInProgress = true
            
            self.lock.unlock()
            
            do {
                try await self.channel.writeAndFlush(writeBuffer)
                
                self.lock.withLock {
                    self.isWriteInProgress = false
                    self.waitingPromises.forEach { $0.succeed(()) }
                    self.waitingPromises.removeAll()
                    
                    // Check if there are any pending flushes
                    if self.buffer.readableBytes > 0 {
                        self.flushWhenIdle()
                    }
                }
            } catch {
                self.lock.withLock {
                    self.isWriteInProgress = false
                    self.waitingPromises.forEach { $0.fail(error) }
                    self.waitingPromises.removeAll()
                }
            }
        }
    }
    
    private func getWriteBuffer() -> ByteBuffer? {
        guard buffer.readableBytes > 0 else {
            return nil
        }
        
        var writeBuffer = channel.allocator.buffer(capacity: buffer.readableBytes)
        writeBuffer.writeBytes(buffer.readableBytesView)
        buffer.clear()

        return writeBuffer
    }
}
