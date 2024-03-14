//
//  File.swift
//  
//
//  Created by mtmk on 14/03/2024.
//

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
    
    func write(data: Data) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                guard buffer.writableBytes >= data.count else {
                    let promise = eventLoop.makePromise(of: Void.self)
                    promise.futureResult.whenSuccess { _ in
                        continuation.resume()
                    }
                    waitingPromises.append(promise)
                    return
                }
                
                buffer.writeBytes(data)
                flush()
                continuation.resume()
            }
        }
    }
    
    private func extractWriteBuffer() -> ByteBuffer? {
        lock.withLock {
            guard self.buffer.readableBytes > 0 else {
                return nil
            }
            
            var writeBuffer = self.channel.allocator.buffer(capacity: self.buffer.readableBytes)
            writeBuffer.writeBytes(self.buffer.readableBytesView)
            self.buffer.clear()
            
            return writeBuffer
        }
    }
    
    func flush() {
        eventLoop.execute {
            self.lock.withLock {
                guard !self.isWriteInProgress else {
                    // A write operation is already in progress, so we wait for it to complete
                    return
                }
                
                guard let writeBuffer = self.extractWriteBuffer() else {
                    return
                }
                
                self.isWriteInProgress = true
                
                let writePromise = self.channel.eventLoop.makePromise(of: Void.self)
                writePromise.futureResult.whenComplete { result in
                    self.lock.withLock {
                        self.isWriteInProgress = false
                        
                        switch result {
                        case .success:
                            self.waitingPromises.forEach { $0.succeed(()) }
                            self.waitingPromises.removeAll()
                        case .failure(let error):
                            self.waitingPromises.forEach { $0.fail(error) }
                            self.waitingPromises.removeAll()
                        }
                        
                        // Check if there are any pending flushes
                        if self.buffer.readableBytes > 0 {
                            self.flush()
                        }
                    }
                }
                
                self.channel.writeAndFlush(writeBuffer, promise: writePromise)
            }
        }
    }
    
    var isEmpty: Bool {
        lock.withLock {
            buffer.readableBytes == 0
        }
    }
    
    var eventLoop: EventLoop {
        self.channel.eventLoop
    }
}

