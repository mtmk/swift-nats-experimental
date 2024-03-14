//
//  File.swift
//  
//
//  Created by mtmk on 12/03/2024.
//

import Foundation
import NatsExperimental
import NIO

print("Starting...")

let client = NatsClient()

try await client.connect(host: "127.0.0.1", port: 4222)
print("Connected to server")

try await client.send("CONNECT {\"verbose\":false}\r\n".data(using: .utf8)!)

let rtt = try await client.ping()
print("connect message sent. rtt=\(rtt)")

let data = "PUB x 128\r\n01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567\r\n".data(using: .utf8)!

print("publishing...")
for _ in 1...100_000 {
    try await client.send(data)
}

let rtt2 = try await client.ping()
print("done. rtt=\(rtt2)")

try client.close()

print("bye")
