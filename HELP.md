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
- [Advanced Peer Discovery Features](#-advanced-peer-discovery-features)
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

### 🌐 Peer Discovery Features
- **DHT (Distributed Hash Table)** - Decentralized peer discovery without trackers
- **PEX (Peer Exchange)** - Peer-to-peer exchange of peer lists
- **Extended Tracker Support** - Multiple public trackers for better coverage

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
├── Bencode            # Bencode encoding/decoding
├── DHT                # Distributed Hash Table for peer discovery
├── PEX                # Peer Exchange for peer list sharing
└── ExtendedTracker    # Extended tracker support with multiple trackers
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
| **DHT** | Decentralized peer discovery using distributed hash table |
| **PEX** | Peer-to-peer exchange of peer lists |
| **ExtendedTracker** | Multiple tracker support with redundancy |

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
}

### DHT (Distributed Hash Table)

Decentralized peer discovery without trackers.

```swift
public class DHTClient {
    // Initialize DHT client
    public init(port: UInt16 = 6881)
    
    // Start DHT client
    public func start() async throws
    
    // Stop DHT client
    public func stop()
    
    // Find peers for a torrent
    public func findPeers(for infoHash: Data) async throws -> [String]
}

public struct DHTNode {
    public let id: Data
    public let address: String
    public let port: UInt16
}

public enum DHTError: Error {
    case encodingFailed
    case receiveFailed
    case invalidNode
    case timeout
}
```

### PEX (Peer Exchange)

Peer-to-peer exchange of peer lists.

```swift
public class PEXClient {
    // Initialize PEX client
    public init()
    
    // Create PEX message
    public func createPEXMessage(peers: [String]) -> Data?
    
    // Parse PEX message
    public func parsePEXMessage(_ data: Data) throws -> PEXMessage
    
    // Process PEX message
    public func processPEXMessage(_ message: PEXMessage)
    
    // Add known peers
    public func addKnownPeers(_ peers: [String])
    
    // Get known peers
    public func getKnownPeers() -> [String]
}

public struct PEXMessage {
    public let added: [String]
    public let addedFlags: [UInt8]
    public let dropped: [String]
}

public enum PEXError: Error {
    case invalidMessageFormat
    case invalidPeerFormat
    case encodingFailed
    case decodingFailed
}
```

### Extended Tracker Support

Multiple tracker support with redundancy.

```swift
public class ExtendedTrackerClient {
    // Initialize with additional trackers
    public init(additionalTrackers: [String] = [])
    
    // Get all available trackers
    public func getAllTrackers(for torrentFile: TorrentFile) -> [String]
    
    // Announce to multiple trackers
    public func announceToMultipleTrackers(
        torrentFile: TorrentFile,
        infoHash: Data,
        peerId: Data,
        port: UInt16,
        uploaded: Int64 = 0,
        downloaded: Int64 = 0,
        left: Int64,
        event: AnnounceEvent = .started
    ) async throws -> ExtendedTrackerResponse
    
    // Scrape multiple trackers
    public func scrapeMultipleTrackers(
        torrentFile: TorrentFile,
        infoHashes: [Data]
    ) async throws -> ExtendedScrapeResponse
    
    // Test tracker connectivity
    public func testTracker(_ tracker: String) async -> Bool
}

public struct ExtendedTrackerResponse {
    public let responses: [TrackerResponse]
    public let errors: [String: Error]
    public let combinedPeers: [String]
    public let totalPeers: Int
    public let successfulTrackers: Int
    public let failedTrackers: Int
}

public struct ExtendedScrapeResponse {
    public let responses: [ScrapeResponse]
    public let errors: [String: Error]
    public let combinedStats: ScrapeResponse
    public let successfulTrackers: Int
    public let failedTrackers: Int
}
    
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

### Advanced Peer Discovery with DHT, PEX, and Extended Trackers

```swift
import SwiftyBT
import Logging

@main
struct AdvancedPeerDiscoveryExample {
    static func main() async {
        // Configure logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }
        
        // Create client with all peer discovery features enabled
        let client = TorrentClient(enableDHT: true, enablePEX: true)
        
        do {
            let session = try client.loadTorrent(from: torrentURL)
            
            print("Torrent: \(session.torrentFile.info.name)")
            print("Size: \(session.torrentFile.getTotalSize()) bytes")
            
            // Start downloading with all peer discovery methods
            try await session.start(downloadPath: "/tmp/downloads")
            
            // Monitor progress with enhanced peer discovery
            while session.getStatus().isRunning {
                let status = session.getStatus()
                print("Progress: \(Int(status.progress * 100))%")
                print("Peers: \(status.peerCount) (from DHT + PEX + Extended Trackers)")
                print("Speed: \(status.downloadSpeed) bytes/s")
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
        } catch {
            print("Error: \(error)")
        }
    }
}
```

### DHT Peer Discovery

```swift
import SwiftyBT

struct DHTExample {
    static func main() async {
        let dhtClient = DHTClient(port: 6881)
        
        do {
            // Start DHT client
            try await dhtClient.start()
            print("DHT client started successfully")
            
            // Create sample info hash
            let infoHash = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
            
            // Find peers using DHT
            let peers = try await dhtClient.findPeers(for: infoHash)
            print("DHT found \(peers.count) peers")
            
            // Process found peers
            for peer in peers {
                print("DHT Peer: \(peer)")
            }
            
        } catch {
            print("DHT error: \(error)")
        }
    }
}
```

### PEX Peer Exchange

```swift
import SwiftyBT

struct PEXExample {
    static func main() async {
        let pexClient = PEXClient()
        
        // Add known peers
        let knownPeers = [
            "192.168.1.100:6881",
            "10.0.0.50:6882",
            "172.16.0.25:6883"
        ]
        pexClient.addKnownPeers(knownPeers)
        
        // Create PEX message
        if let pexMessage = pexClient.createPEXMessage(peers: knownPeers) {
            print("Created PEX message with \(knownPeers.count) peers")
            print("Message size: \(pexMessage.count) bytes")
        }
        
        // Simulate receiving PEX message
        let newPeers = ["203.0.113.10:6881", "198.51.100.20:6882"]
        let pexMessageData = pexClient.createPEXMessage(peers: newPeers)
        
        if let messageData = pexMessageData {
            do {
                let receivedMessage = try pexClient.parsePEXMessage(messageData)
                pexClient.processPEXMessage(receivedMessage)
                print("Processed PEX message with \(receivedMessage.added.count) new peers")
            } catch {
                print("PEX error: \(error)")
            }
        }
    }
}
```

### Extended Tracker Support

```swift
import SwiftyBT

struct ExtendedTrackerExample {
    static func main() async {
        let extendedTracker = ExtendedTrackerClient()
        
        // Create sample torrent file
        let torrentFile = try TorrentFile.parse(from: torrentURL)
        
        // Get all available trackers (including public trackers)
        let allTrackers = extendedTracker.getAllTrackers(for: torrentFile)
        print("Total trackers available: \(allTrackers.count)")
        
        // Test tracker connectivity
        for tracker in allTrackers.prefix(5) {
            let isWorking = await extendedTracker.testTracker(tracker)
            print("Tracker \(tracker): \(isWorking ? "Working" : "Failed")")
        }
        
        // Announce to multiple trackers
        do {
            let response = try await extendedTracker.announceToMultipleTrackers(
                torrentFile: torrentFile,
                infoHash: infoHash,
                peerId: peerId,
                port: 6881,
                uploaded: 0,
                downloaded: 0,
                left: torrentFile.getTotalSize(),
                event: .started
            )
            
            print("Extended tracker response:")
            print("- Total peers: \(response.totalPeers)")
            print("- Successful trackers: \(response.successfulTrackers)")
            print("- Failed trackers: \(response.failedTrackers)")
            
        } catch {
            print("Extended tracker error: \(error)")
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

## 🌟 Advanced Peer Discovery Features

SwiftyBT now includes three major peer discovery enhancements that significantly improve BitTorrent performance and reliability.

### DHT (Distributed Hash Table)

**What is DHT?**
DHT is a decentralized peer discovery mechanism that allows BitTorrent clients to find peers without relying on centralized trackers. It uses a distributed hash table to store and retrieve peer information.

**Key Benefits:**
- **Decentralized**: No dependency on centralized trackers
- **Scalable**: Can handle large numbers of peers
- **Resilient**: Continues working even if some nodes fail
- **Automatic**: Integrated seamlessly into the torrent client

**Technical Implementation:**
- **Protocol**: Kademlia DHT protocol
- **Network**: UDP-based communication
- **Routing**: XOR-based distance metric
- **Bootstrap**: Automatic bootstrap with known nodes

### PEX (Peer Exchange)

**What is PEX?**
PEX allows BitTorrent clients to exchange peer lists directly with each other, reducing the need for tracker requests and improving peer discovery efficiency.

**Key Benefits:**
- **Efficient**: Reduces tracker requests
- **Fast**: Direct peer-to-peer communication
- **Automatic**: Integrated into peer communication
- **Standard**: Implements BitTorrent PEX protocol

**Technical Implementation:**
- **Protocol**: BitTorrent PEX extension protocol
- **Messages**: Bencoded peer lists
- **Integration**: Seamless integration with peer wire protocol
- **Limits**: Configurable peer limits and message sizes

### Extended Tracker Support

**What are Extended Trackers?**
Extended tracker support adds multiple public trackers to supplement the trackers specified in the torrent file, providing better peer coverage and redundancy.

**Key Benefits:**
- **Multiple Trackers**: Uses both torrent file trackers and public trackers
- **Redundancy**: If some trackers fail, others continue working
- **Better Coverage**: More trackers mean more potential peers
- **Automatic**: No configuration required

**Technical Implementation:**
- **Concurrent Requests**: Multiple tracker announces simultaneously
- **Response Aggregation**: Combines responses from multiple trackers
- **Error Handling**: Graceful handling of tracker failures
- **Deduplication**: Removes duplicate peers across trackers

### Combined Performance Benefits

When all three features work together, you get:

**Peer Discovery:**
- **Traditional Trackers**: From torrent file
- **DHT**: Decentralized peer discovery
- **PEX**: Peer-to-peer exchange
- **Extended Trackers**: Additional public trackers

**Combined Benefits:**
- **Higher Peer Count**: More sources for peer discovery
- **Better Connectivity**: Redundancy across multiple methods
- **Faster Discovery**: Multiple simultaneous discovery methods
- **Improved Reliability**: If one method fails, others continue

### Configuration Options

**DHT Configuration:**
- **Port**: Default 6881 (configurable)
- **Bootstrap Nodes**: Automatic bootstrap with known DHT nodes
- **Routing Table**: Automatic management of DHT routing table

**PEX Configuration:**
- **Extension ID**: Standard PEX extension ID (1)
- **Message Format**: Bencoded PEX messages
- **Peer Limits**: Configurable limits for peer exchange

**Extended Tracker Configuration:**
- **Public Trackers**: Comprehensive list of reliable public trackers
- **Concurrent Announces**: Up to 5 concurrent tracker announces
- **Timeout**: Configurable timeout for tracker requests

### Migration Guide

**For Existing Users:**
No changes required! All new features are backward compatible:

```swift
// Old code still works
let client = TorrentClient()
let session = try client.loadTorrent(from: torrentURL)
try await session.start(downloadPath: "/path/to/downloads")

// New features are automatically enabled for better performance
```

**For New Users:**
Enable all features for optimal performance:

```swift
// Recommended configuration
let client = TorrentClient(enableDHT: true, enablePEX: true)
let session = try client.loadTorrent(from: torrentURL)
try await session.start(downloadPath: "/path/to/downloads")
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
