# SwiftyBT

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

// Create a torrent client
let client = TorrentClient()

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
let client = TorrentClient()

// Load multiple torrents
let session1 = try client.loadTorrent(from: url1)
let session2 = try client.loadTorrent(from: url2)

// Start them concurrently
try await withTaskGroup(of: Void.self) { group in
    group.addTask { try await session1.start() }
    group.addTask { try await session2.start() }
}
```

## ✨ Features

- **Full BitTorrent Protocol Support** - Complete implementation of the BitTorrent protocol
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

---

**SwiftyBT** - Modern BitTorrent client library for Swift

Built with ❤️ using Swift Concurrency and SwiftNIO 
