# SwiftyBT - Detailed Documentation

Documentation for SwiftyBT 

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Core Components](#architecture)
- [Concurrency Model](#concurrency-model)
- [API Reference](#api-reference)
- [Examples](#examples)
- [Development](#development)

## 🚀 Overview

SwiftyBT is a comprehensive BitTorrent client library that provides:

- **Full BitTorrent Protocol Support** - Complete implementation of the BitTorrent protocol
- **Concurrent Torrent Management** - Handle multiple torrents simultaneously
- **Modern Swift Concurrency** - Built with async/await and SwiftNIO
- **High Performance** - Non-blocking I/O with efficient resource utilization
- **Cross-Platform** - Support for macOS and iOS

The library is designed with performance and scalability in mind, utilizing modern Swift concurrency patterns and the SwiftNIO framework for high-throughput network operations.

## ✨ Features

### 🔧 Core Functionality
- **Torrent File Parsing** - Parse and validate .torrent files
- **Tracker Communication** - HTTP/HTTPS tracker announce and scrape
- **Peer Wire Protocol** - Full BitTorrent peer communication
- **Bencode Encoding/Decoding** - BitTorrent's bencode format support
- **Piece Management** - Efficient piece requesting and validation

### 🚀 Advanced Features
- **Concurrent Torrent Sessions** - Manage multiple torrents simultaneously
- **Asynchronous Operations** - Non-blocking I/O with async/await
- **Event Loop Architecture** - High-performance network handling
- **Comprehensive Logging** - Detailed logging with Swift Log
- **Error Handling** - Robust error handling and recovery

### 📊 Monitoring & Control
- **Real-time Statistics** - Download/upload speeds, progress tracking
- **Peer Management** - Dynamic peer connection handling
- **Session Control** - Start, stop, and pause torrent sessions
- **Status Monitoring** - Comprehensive torrent status information

## 📋 Requirements

- **Swift**: 6.0+
- **Platforms**: 
  - macOS 13.0+
  - Linux
- **Dependencies**:
  - Swift Crypto 2.0.0+
  - Swift NIO 2.0.0+
  - Swift NIO SSL 2.0.0+
  - Swift Log 1.0.0+

## 📦 Installation

### Swift Package Manager

Add SwiftyBT to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/SwiftyBT.git", from: "1.0.0")
]
```

Or add it to your Xcode project:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select the version and add to your target

## 🏗️ Core Components

```
SwiftyBT/
├── TorrentClient      # Main client for managing multiple torrents
├── TorrentSession     # Individual torrent session management
├── TorrentFile        # Torrent file parsing and validation
├── PeerWire           # BitTorrent peer wire protocol
├── Tracker            # Tracker communication (HTTP/HTTPS)
└── Bencode            # Bencode encoding/decoding
```

### Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **TorrentClient** | Manages multiple torrent sessions, provides high-level API |
| **TorrentSession** | Handles individual torrent lifecycle and peer management |
| **TorrentFile** | Parses .torrent files, validates metadata |
| **PeerWire** | Implements BitTorrent peer wire protocol |
| **Tracker** | Handles tracker announce/scrape operations |
| **Bencode** | Encodes/decodes BitTorrent bencode format |

## 🔄 Concurrency Model

SwiftyBT leverages modern Swift concurrency to provide high-performance, non-blocking operations.

### Event Loop Architecture

The library uses **SwiftNIO's Event Loop Group** for efficient network I/O:

```swift
private let eventLoopGroup: EventLoopGroup
// Default: MultiThreadedEventLoopGroup(numberOfThreads: 1)
```

**Key Benefits:**
- **Non-blocking I/O** - Single thread can handle multiple connections
- **Efficient Resource Usage** - Minimal thread overhead
- **Scalable** - Easy to scale across multiple cores

### Async/Await Pattern

All network operations use Swift's async/await for clean, readable code:

```swift
// Async torrent operations
public func start(downloadPath: String? = nil) async throws
public func stop() async

// Async peer communication
public func sendRequest(pieceIndex: UInt32, offset: UInt32, length: UInt32) async throws
public func sendInterested() async throws

// Async tracker communication
public func announce(url: String, infoHash: Data, ...) async throws -> TrackerResponse
```

### Concurrent Torrent Management

The library supports **true concurrency** for multiple torrents:

```swift
// Multiple torrents run independently
private var activeTorrents: [String: TorrentSession] = [:]

// Each session has its own peer connections
private var peerConnections: [String: PeerConnection] = [:]
```

### Parallel Operations

**Tracker Communication:**
```swift
// Parallel tracker announces
for tracker in trackers {
    let response = try await trackerClient.announce(...)
    // Each tracker processed independently
}
```

**Peer Connections:**
```swift
// Parallel peer connections
for peer in response.peers {
    try await connectToPeer(peer)
    // Each peer handled independently
}
```

**Piece Requests:**
```swift
// Parallel piece requests
for pieceIndex in 0..<torrentFile.info.pieces.count {
    for offset in stride(from: 0, to: pieceSize, by: blockSize) {
        try await connection.sendRequest(...)
    }
}
```

### Thread Safety

- **Immutable Data** - TorrentFile and metadata are thread-safe
- **Actor-like Sessions** - Each TorrentSession manages its own state
- **Concurrent Collections** - Safe access to shared resources

## 📚 API Reference

### TorrentClient

The main entry point for managing multiple torrents.

```swift
public class TorrentClient {
    // Initialize with custom event loop group
    public init(eventLoopGroup: EventLoopGroup? = nil)
    
    // Load torrent from file
    public func loadTorrent(from url: URL) throws -> TorrentSession
    
    // Load torrent from data
    public func loadTorrent(from data: Data) throws -> TorrentSession
    
    // Get active session
    public func getTorrentSession(infoHashHex: String) -> TorrentSession?
    
    // Get all active sessions
    public func getAllTorrentSessions() -> [TorrentSession]
    
    // Remove session
    public func removeTorrentSession(infoHashHex: String)
}
```

### TorrentSession

Manages individual torrent lifecycle and operations.

```swift
public class TorrentSession {
    // Start torrent session
    public func start(downloadPath: String? = nil) async throws
    
    // Stop torrent session
    public func stop() async
    
    // Get current status
    public func getStatus() -> TorrentStatus
    
    // Properties
    public let torrentFile: TorrentFile
    public let infoHash: Data
    public let infoHashHex: String
}
```

### TorrentStatus

Comprehensive status information for a torrent.

```swift
public struct TorrentStatus {
    public let name: String
    public let infoHash: String
    public let totalSize: Int
    public let downloadedBytes: Int64
    public let uploadedBytes: Int64
    public let leftBytes: Int64
    public let progress: Double
    public let uploadSpeed: Int64
    public let downloadSpeed: Int64
    public let peerCount: Int
    public let isRunning: Bool
}
```

### PeerWire

BitTorrent peer wire protocol implementation.

```swift
public class PeerWireClient {
    // Connect to peer
    public func connect(to address: String, port: UInt16, infoHash: Data, peerId: Data) async throws -> PeerConnection
}

public class PeerConnection {
    // Send messages
    public func sendInterested() async throws
    public func sendNotInterested() async throws
    public func sendChoke() async throws
    public func sendUnchoke() async throws
    public func sendHave(pieceIndex: UInt32) async throws
    public func sendBitfield(_ bitfield: [Bool]) async throws
    public func sendRequest(pieceIndex: UInt32, offset: UInt32, length: UInt32) async throws
    public func sendPiece(pieceIndex: UInt32, offset: UInt32, data: Data) async throws
    public func sendCancel(pieceIndex: UInt32, offset: UInt32, length: UInt32) async throws
    public func sendPort(port: UInt16) async throws
    public func close() async throws
    
    // Get peer state
    public func getPeerBitfield() async -> [Bool]?
    public func isPeerChoked() async -> Bool
    public func isPeerInterested() async -> Bool
}
```

### Tracker

Tracker communication for peer discovery.

```swift
public class TrackerClient {
    // Announce to tracker
    public func announce(url: String, infoHash: Data, peerId: Data, port: UInt16, uploaded: Int64, downloaded: Int64, left: Int64, event: AnnounceEvent) async throws -> TrackerResponse
    
    // Scrape tracker for statistics
    public func scrape(url: String, infoHashes: [Data]) async throws -> ScrapeResponse
}

public struct TrackerResponse {
    public let interval: Int
    public let minInterval: Int
    public let complete: Int
    public let incomplete: Int
    public let peers: [Peer]
}

public struct Peer {
    public let address: String
    public let port: UInt16
}
```

### Bencode

BitTorrent's bencode format support.

```swift
public enum Bencode {
    // Parse bencode data
    public static func parse(_ data: Data) throws -> BencodeValue
    public static func parse(_ string: String) throws -> BencodeValue
    
    // Encode to data
    public static func encode(_ value: BencodeValue) -> Data
}

public enum BencodeValue {
    case string(String)
    case integer(Int64)
    case list([BencodeValue])
    case dictionary([String: BencodeValue])
}
```

## 💡 Examples

### Basic Torrent Download

```swift
import SwiftyBT
import Logging

// Configure logging
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

@main
struct TorrentExample {
    static func main() async {
        let client = TorrentClient()
        
        do {
            let session = try client.loadTorrent(from: torrentURL)
            
            print("Torrent: \(session.torrentFile.info.name)")
            print("Size: \(session.torrentFile.getTotalSize()) bytes")
            print("Pieces: \(session.torrentFile.info.pieces.count)")
            
            try await session.start(downloadPath: "/tmp/downloads")
            
            // Monitor progress
            while session.getStatus().isRunning {
                let status = session.getStatus()
                print("Progress: \(Int(status.progress * 100))%")
                print("Speed: \(status.downloadSpeed) bytes/s")
                print("Peers: \(status.peerCount)")
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### Multiple Torrents with Progress Monitoring

```swift
import SwiftyBT

struct MultiTorrentExample {
    static func main() async {
        let client = TorrentClient()
        let torrentURLs = [url1, url2, url3]
        
        // Load all torrents
        var sessions: [TorrentSession] = []
        for url in torrentURLs {
            do {
                let session = try client.loadTorrent(from: url)
                sessions.append(session)
            } catch {
                print("Failed to load torrent: \(error)")
            }
        }
        
        // Start all torrents concurrently
        try await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask {
                    try await session.start(downloadPath: "/tmp/downloads")
                }
            }
        }
        
        // Monitor all torrents
        while sessions.contains(where: { $0.getStatus().isRunning }) {
            print("\n=== Torrent Status ===")
            for session in sessions {
                let status = session.getStatus()
                print("\(status.name): \(Int(status.progress * 100))% " +
                      "(\(status.downloadSpeed) bytes/s, \(status.peerCount) peers)")
            }
            
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
    }
}
```

### Custom Tracker Communication

```swift
import SwiftyBT

struct TrackerExample {
    static func main() async {
        let trackerClient = TrackerClient()
        
        let infoHash = Data(/* your info hash */)
        let peerId = Data(/* your peer ID */)
        
        do {
            let response = try await trackerClient.announce(
                url: "http://tracker.example.com:6881/announce",
                infoHash: infoHash,
                peerId: peerId,
                port: 6881,
                uploaded: 0,
                downloaded: 0,
                left: 1000000,
                event: .started
            )
            
            print("Tracker returned \(response.peers.count) peers")
            for peer in response.peers {
                print("Peer: \(peer.address):\(peer.port)")
            }
            
        } catch {
            print("Tracker error: \(error)")
        }
    }
}
```

### Direct Peer Communication

```swift
import SwiftyBT

struct PeerExample {
    static func main() async {
        let peerWireClient = PeerWireClient()
        
        let infoHash = Data(/* your info hash */)
        let peerId = Data(/* your peer ID */)
        
        do {
            let connection = try await peerWireClient.connect(
                to: "peer.example.com",
                port: 6881,
                infoHash: infoHash,
                peerId: peerId
            )
            
            // Send interested message
            try await connection.sendInterested()
            
            // Send bitfield (pieces we have)
            let bitfield = Array(repeating: false, count: 1000)
            try await connection.sendBitfield(bitfield)
            
            // Request pieces
            try await connection.sendRequest(pieceIndex: 0, offset: 0, length: 16384)
            
            // Close connection
            try await connection.close()
            
        } catch {
            print("Peer error: \(error)")
        }
    }
}
```

### Bencode Parsing

```swift
import SwiftyBT

struct BencodeExample {
    static func main() async {
        // Parse bencode data
        let bencodeString = "d4:name5:teste"
        
        do {
            let value = try Bencode.parse(bencodeString)
            print("Parsed: \(value)")
            
            // Encode back to data
            let encoded = Bencode.encode(value)
            let encodedString = String(data: encoded, encoding: .utf8) ?? "invalid"
            print("Encoded: \(encodedString)")
            
        } catch {
            print("Bencode error: \(error)")
        }
    }
}
```

### Advanced: Custom Event Loop Configuration

```swift
import SwiftyBT
import NIOPosix

struct AdvancedExample {
    static func main() async {
        // Create custom event loop group with multiple threads
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 4)
        
        // Create client with custom event loop
        let client = TorrentClient(eventLoopGroup: eventLoopGroup)
        
        // Use client as normal...
        let session = try client.loadTorrent(from: torrentURL)
        try await session.start()
        
        // Clean up
        try eventLoopGroup.syncShutdownGracefully()
    }
}
```

## 🛠️ Development

### Development Setup

1. Clone the repository
2. Open in Xcode or use Swift Package Manager
3. Run tests: `swift test`
4. Build: `swift build`

### Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter TorrentClientTests

# Build for release
swift build -c release
```

### Error Handling

The library provides comprehensive error types:

```swift
public enum TorrentFileError: Error {
    case invalidFile
    case invalidBencode
    case missingInfo
    case invalidInfoHash
}

public enum PeerWireError: Error {
    case connectionFailed
    case handshakeFailed
    case invalidMessage
    case peerChoked
}

public enum TrackerError: Error {
    case invalidURL
    case networkError
    case invalidResponse
}
```

---

For quick start and basic usage, see [README.md](README.md). 
