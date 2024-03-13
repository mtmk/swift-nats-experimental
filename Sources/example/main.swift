//
//  File.swift
//  
//
//  Created by mtmk on 12/03/2024.
//

import Foundation
import NatsExperimental
import NIO

print("Starting example...")

// Create an EventLoopGroup
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

// Get an EventLoop from the group
let eventLoop = group.next()

// Schedule a task on the EventLoop
eventLoop.execute {
    print("Task executed on the EventLoop")
}

// Schedule a future task on the EventLoop
let schedule = eventLoop.scheduleTask(in: .seconds(1)) {
    return "Future result"
}

// Wait for the future result
do {
    let result = try await schedule.futureResult.get()
    print("Future result:", result)
} catch {
    print("Error waiting for future result:", error)
}

// Shutdown the EventLoopGroup when you're done
try? await group.shutdownGracefully()

/*========================================================*/


let client = NatsClient()

try await client.connect(host: "127.0.0.1", port: 4222)
print("Connected to server")

try await client.send("CONNECT {\"verbose\":false}\r\n".data(using: .utf8)!)
let rtt = try await client.ping()
print("connect message sent. rtt=\(rtt)")

let data = "PUB x 128\r\n01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567\r\n".data(using: .utf8)!

for _ in 1...10_000 {
    try await client.send(data)
}

let rtt2 = try await client.ping()
print("done. rtt=\(rtt2)")

try client.close()

