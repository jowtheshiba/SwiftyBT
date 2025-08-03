# SwiftyBT

[![Version](https://img.shields.io/badge/Version-1.0.0-blue.svg)](https://github.com/your-username/SwiftyBT)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A modern BitTorrent client library written in Swift.

## 🚀 Quick Start

### Installation

Add SwiftyBT to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/SwiftyBT.git", from: "1.0.0")
]
```

### Basic Usage

```swift
import SwiftyBT

// Create a torrent client with DHT and PEX enabled
let client = TorrentClient(enableDHT: true, enablePEX: true)

// Load a torrent file
let session = try client.loadTorrent(from: torrentURL)

// Start downloading
try await session.start(downloadPath: "/path/to/downloads")

// Monitor progress
let status = session.getStatus()
print("Progress: \(Int(status.progress * 100))%")
```

### Multiple Torrents

```swift
let client = TorrentClient(enableDHT: true, enablePEX: true)

// Load multiple torrents
let session1 = try client.loadTorrent(from: url1)
let session2 = try client.loadTorrent(from: url2)

// Start them concurrently
try await withTaskGroup(of: Void.self) { group in
    group.addTask { try await session1.start() }
    group.addTask { try await session2.start() }
}
```

---

## 🛠️ CLI Tool: clt-swiftybt

A simple command-line torrent downloader is available in the [clt-swiftybt](clt-swiftybt/) subdirectory:

- Download one or more `.torrent` files from the command line
- Progress bar and real-time stats for each torrent
- Downloads to `torrent_downloads` folder in the current directory

**See [clt-swiftybt/README.md](clt-swiftybt/README.md) for usage and installation.**

---

### Advanced Features

#### DHT Peer Discovery
```swift
// DHT is automatically enabled and will find peers without trackers
let client = TorrentClient(enableDHT: true)
let session = try client.loadTorrent(from: torrentURL)

// DHT will automatically discover peers in the distributed network
try await session.start()
```

#### PEX Peer Exchange
```swift
// PEX enables peer-to-peer exchange of peer lists
let client = TorrentClient(enablePEX: true)
let session = try client.loadTorrent(from: torrentURL)

// PEX will automatically exchange peer lists with connected peers
try await session.start()
```

#### Extended Tracker Support
```swift
// Extended trackers provide additional public trackers for better coverage
let client = TorrentClient()
let session = try client.loadTorrent(from: torrentURL)

// Will announce to both torrent trackers and public trackers
try await session.start()
```

## ✨ Features

- **Full BitTorrent Protocol Support** - Complete implementation of the BitTorrent protocol
- **DHT Support** - Distributed Hash Table for decentralized peer discovery
- **PEX Support** - Peer Exchange for efficient peer list sharing
- **Extended Tracker Support** - Multiple public trackers for better coverage
- **Concurrent Torrent Management** - Handle multiple torrents simultaneously
- **Modern Swift Concurrency** - Built with async/await and SwiftNIO
- **High Performance** - Non-blocking I/O with efficient resource utilization
- **Cross-Platform** - Support for macOS and Linux

## 📋 Requirements

- **Swift**: 6.0+
- **Platforms**: macOS 13.0+, Linux
- **Dependencies**: Swift Crypto, Swift NIO, Swift NIO SSL, Swift Log

## 📚 Documentation

For detailed documentation, examples, and API reference, see [HELP.md](HELP.md).
