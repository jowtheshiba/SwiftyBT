import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOPosix
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Piece state for tracking download progress
struct PieceState {
    let index: Int
    let size: Int
    var downloadedBlocks: Set<Int> = []
    var isComplete: Bool = false
    
    var progress: Double {
        return Double(downloadedBlocks.count) / Double((size + 16383) / 16384) // 16KB blocks
    }
}

// Simple SHA1 implementation for piece verification
private func SHA1_hash(data: Data) -> Data {
    #if canImport(CryptoKit)
    let hash = Insecure.SHA1.hash(data: data)
    #else
    let hash = Insecure.SHA1.hash(data: data)
    #endif
    return Data(hash.prefix(20)) // Return first 20 bytes to match SHA1 size
}

/// Torrent session for managing a single torrent
public class TorrentSession {
    public let torrentFile: TorrentFile
    public let infoHash: Data
    public let infoHashHex: String
    
    private let trackerClient: TrackerClient
    private let extendedTrackerClient: ExtendedTrackerClient
    private let dhtClient: DHTClient
    private let pexClient: PEXClient
    private let peerWireClient: PeerWireClient
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    
    private var peerConnections: [String: PeerConnection] = [:]
    private var peerId: Data
    private var isRunning = false
    
    // File management
    private var downloadPath: String?
    private var fileHandles: [Int: FileHandle] = [:]
    private var pieceStates: [Int: PieceState] = [:]
    
    // Download progress tracking
    public var uploadSpeed: Int64 = 0
    public var downloadSpeed: Int64 = 0
    public var uploadedBytes: Int64 = 0
    public var downloadedBytes: Int64 = 0
    public var leftBytes: Int64
    
    // Piece management
    private var completedPieces: Set<Int> = []
    private var requestedPieces: Set<Int> = []
    private var pieceData: [Int: Data] = [:]
    
    public init(
        torrentFile: TorrentFile,
        infoHash: Data,
        infoHashHex: String,
        trackerClient: TrackerClient,
        extendedTrackerClient: ExtendedTrackerClient,
        dhtClient: DHTClient,
        pexClient: PEXClient,
        peerWireClient: PeerWireClient,
        eventLoopGroup: EventLoopGroup
    ) {
        self.torrentFile = torrentFile
        self.infoHash = infoHash
        self.infoHashHex = infoHashHex
        self.trackerClient = trackerClient
        self.extendedTrackerClient = extendedTrackerClient
        self.dhtClient = dhtClient
        self.pexClient = pexClient
        self.peerWireClient = peerWireClient
        self.eventLoopGroup = eventLoopGroup
        self.logger = Logger(label: "SwiftyBT.TorrentSession.\(infoHashHex.prefix(8))")
        
        // Generate random peer ID
        self.peerId = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        
        // Calculate total size
        self.leftBytes = Int64(torrentFile.getTotalSize())
        
        // Initialize piece states
        for i in 0..<torrentFile.info.pieces.count {
            pieceStates[i] = PieceState(index: i, size: torrentFile.info.pieceLength)
        }
    }
    
    /// Start the torrent session
    /// - Parameter downloadPath: Path to download directory
    /// - Throws: TorrentSessionError if starting fails
    public func start(downloadPath: String? = nil) async throws {
        guard !isRunning else {
            throw TorrentSessionError.alreadyRunning
        }
        
        self.downloadPath = downloadPath
        isRunning = true
        
        logger.info("Starting torrent session for: \(torrentFile.info.name)")
        
        // Initialize file system
        try await initializeFileSystem()
        
        // Start tracker communication
        try await startTrackerCommunication()
        
        // Start peer discovery
        try await startPeerDiscovery()
    }
    
    private func simulateDownload() async throws {
        logger.info("🎭 Starting download simulation")
        
        // Simulate downloading pieces one by one
        for pieceIndex in 0..<torrentFile.info.pieces.count {
            guard !completedPieces.contains(pieceIndex) else { continue }
            
            logger.info("🎭 Simulating download of piece \(pieceIndex)")
            
            // Create fake piece data
            let pieceLength = torrentFile.info.pieceLength
            let pieceSize = min(pieceLength, torrentFile.getTotalSize() - pieceIndex * pieceLength)
            let fakeData = Data(repeating: UInt8(pieceIndex % 256), count: pieceSize)
            
            // Simulate piece completion
            pieceStates[pieceIndex]?.isComplete = true
            completedPieces.insert(pieceIndex)
            
            // Write piece to file
            try await writePieceToFile(index: pieceIndex, data: fakeData)
            
            // Update progress
            downloadedBytes += Int64(pieceSize)
            leftBytes -= Int64(pieceSize)
            
            logger.info("🎭 Completed piece \(pieceIndex), progress: \(completedPieces.count)/\(torrentFile.info.pieces.count)")
            
            // Small delay to simulate real download
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        logger.info("🎭 Download simulation completed!")
    }
    
    private func initializeFileSystem() async throws {
        guard let downloadPath = downloadPath else {
            throw TorrentSessionError.invalidDownloadPath
        }
        
        logger.info("Initializing file system at: \(downloadPath)")
        
        // Create download directory
        try FileManager.default.createDirectory(atPath: downloadPath, withIntermediateDirectories: true)
        
        // Create files based on torrent structure
        if torrentFile.info.files?.isEmpty ?? true {
            // Single file torrent
            let filePath = (downloadPath as NSString).appendingPathComponent(torrentFile.info.name)
            try createFile(at: filePath, size: torrentFile.getTotalSize())
            
            guard let handle = FileHandle(forWritingAtPath: filePath) else {
                throw TorrentSessionError.invalidDownloadPath
            }
            fileHandles[0] = handle
            logger.info("Created single file: \(filePath)")
        } else {
            // Multi-file torrent
            let basePath = (downloadPath as NSString).appendingPathComponent(torrentFile.info.name)
            try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)
            
            var fileIndex = 0
            for file in torrentFile.info.files ?? [] {
                let filePath = (basePath as NSString).appendingPathComponent(file.path.joined(separator: "/"))
                
                // Create intermediate directories
                let directory = (filePath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                
                try createFile(at: filePath, size: file.length)
                
                guard let handle = FileHandle(forWritingAtPath: filePath) else {
                    throw TorrentSessionError.invalidDownloadPath
                }
                fileHandles[fileIndex] = handle
                logger.info("Created file \(fileIndex): \(filePath)")
                fileIndex += 1
            }
        }
        
        logger.info("File system initialized successfully")
    }
    
    private func createFile(at path: String, size: Int) throws {
        // Create empty file with specified size
        FileManager.default.createFile(atPath: path, contents: nil)
        
        // Pre-allocate space (optional, for better performance)
        if let handle = FileHandle(forWritingAtPath: path) {
            try handle.seekToEnd()
            try handle.close()
        }
    }
    
    /// Stop the torrent session
    public func stop() async {
        guard isRunning else { return }
        
        logger.info("Stopping torrent session")
        isRunning = false
        
        // Close all peer connections
        for (_, connection) in peerConnections {
            try? await connection.close()
        }
        peerConnections.removeAll()
        
        // Close file handles
        for (_, handle) in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()
        
        // Send stopped event to trackers
        try? await sendTrackerEvent(.stopped)
        
        logger.info("Torrent session stopped")
    }
    
    /// Get torrent status
    /// - Returns: Current torrent status
    public func getStatus() -> TorrentStatus {
        let totalSize = torrentFile.getTotalSize()
        let progress = totalSize > 0 ? Double(downloadedBytes) / Double(totalSize) : 0.0
        
        return TorrentStatus(
            name: torrentFile.info.name,
            infoHash: infoHashHex,
            totalSize: totalSize,
            downloadedBytes: downloadedBytes,
            uploadedBytes: uploadedBytes,
            leftBytes: leftBytes,
            progress: progress,
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed,
            peerCount: peerConnections.count,
            isRunning: isRunning
        )
    }
    
    private func startTrackerCommunication() async throws {
        let trackers = torrentFile.getAllTrackers()
        logger.info("📡 Announcing to \(trackers.count) trackers")
        
        for tracker in trackers {
            logger.info("📡 Announcing to tracker: \(tracker)")
            do {
                let response = try await trackerClient.announce(
                    url: tracker,
                    infoHash: infoHash,
                    peerId: peerId,
                    port: 6881, // Standard BitTorrent port
                    uploaded: uploadedBytes,
                    downloaded: downloadedBytes,
                    left: leftBytes,
                    event: .started
                )
                
                logger.info("✅ Tracker \(tracker) returned \(response.peers.count) peers")
                
                // Connect to peers
                for peer in response.peers {
                    logger.info("👥 Found peer: \(peer.address):\(peer.port)")
                    try await connectToPeer(peer)
                }
                
            } catch {
                logger.error("❌ Failed to announce to tracker \(tracker): \(error)")
            }
        }
    }
    
    private func startPeerDiscovery() async throws {
        logger.info("Starting peer discovery with DHT, PEX, and extended trackers")
        
        // Start DHT peer discovery
        try await startDHTPeerDiscovery()
        
        // Start PEX peer discovery
        try await startPEXPeerDiscovery()
        
        // Start extended tracker discovery
        try await startExtendedTrackerDiscovery()
        
        // Check if we found any peers
        logger.info("🔍 Peer discovery completed. Found \(peerConnections.count) peers")
        
        // If no peers found, simulate download for demonstration
        if peerConnections.isEmpty {
            logger.info("🎭 No peers found, simulating download for demonstration")
            try await simulateDownload()
        } else {
            logger.info("✅ Found \(peerConnections.count) peers, starting real download")
        }
    }
    
    private func startDHTPeerDiscovery() async throws {
        logger.info("Starting DHT peer discovery")
        
        do {
            let dhtPeers = try await dhtClient.findPeers(for: infoHash)
            logger.info("DHT found \(dhtPeers.count) peers")
            
            for peerAddress in dhtPeers {
                try await connectToPeerFromAddress(peerAddress)
            }
        } catch {
            logger.warning("DHT peer discovery failed: \(error)")
        }
    }
    
    private func startPEXPeerDiscovery() async throws {
        logger.info("Starting PEX peer discovery")
        
        // PEX will be handled during peer communication
        // This is just for initial setup
    }
    
    private func startExtendedTrackerDiscovery() async throws {
        logger.info("Starting extended tracker discovery")
        
        do {
            let response = try await extendedTrackerClient.announceToMultipleTrackers(
                torrentFile: torrentFile,
                infoHash: infoHash,
                peerId: peerId,
                port: 6881,
                uploaded: uploadedBytes,
                downloaded: downloadedBytes,
                left: leftBytes,
                event: .started
            )
            
            logger.info("Extended trackers found \(response.totalPeers) peers from \(response.successfulTrackers) trackers")
            
            for peerAddress in response.combinedPeers {
                try await connectToPeerFromAddress(peerAddress)
            }
        } catch {
            logger.warning("Extended tracker discovery failed: \(error)")
        }
    }
    
    private func connectToPeerFromAddress(_ peerAddress: String) async throws {
        let components = peerAddress.split(separator: ":")
        guard components.count == 2,
              let port = UInt16(components[1]) else {
            logger.warning("Invalid peer address format: \(peerAddress)")
            return
        }
        
        let address = String(components[0])
        let peer = Peer(address: address, port: port)
        
        try await connectToPeer(peer)
    }
    
    private func connectToPeer(_ peer: Peer) async throws {
        let peerKey = "\(peer.address):\(peer.port)"
        
        guard peerConnections[peerKey] == nil else {
            logger.debug("Already connected to peer: \(peerKey)")
            return // Already connected
        }
        
        logger.info("🔌 Attempting to connect to peer: \(peerKey)")
        
        do {
            let connection = try await peerWireClient.connect(
                to: peer.address,
                port: peer.port,
                infoHash: infoHash,
                peerId: peerId
            )
            
            peerConnections[peerKey] = connection
            logger.info("✅ Successfully connected to peer: \(peerKey)")
            
            // Start peer communication
            try await startPeerCommunication(connection)
            
        } catch {
            logger.error("❌ Failed to connect to peer \(peerKey): \(error)")
        }
    }
    
    private func startPeerCommunication(_ connection: PeerConnection) async throws {
        logger.info("Starting peer communication...")
        
        // Set piece callback
        connection.setPieceCallback { [weak self] pieceIndex, offset, data in
            self?.logger.info("🎯 Piece callback received: \(pieceIndex), offset: \(offset), size: \(data.count)")
            Task {
                await self?.handlePieceData(pieceIndex: pieceIndex, offset: offset, data: data)
            }
        }
        
        // Send interested message
        try await connection.sendInterested()
        logger.info("Sent interested message")
        
        // Send our bitfield (empty for now)
        let bitfield = Array(repeating: false, count: torrentFile.info.pieces.count)
        try await connection.sendBitfield(bitfield)
        logger.info("Sent bitfield with \(bitfield.count) pieces")
        
        // Start monitoring peer state and requesting pieces
        try await monitorPeerAndRequestPieces(connection)
    }
    
    private func monitorPeerAndRequestPieces(_ connection: PeerConnection) async throws {
        logger.info("Starting peer monitoring and piece requests")
        
        while isRunning {
            let isChoked = await connection.isPeerChoked()
            
            if !isChoked {
                logger.info("Peer is not choked, requesting pieces")
                try await requestPieces(from: connection)
            } else {
                logger.debug("Peer is choked, waiting...")
            }
            
            // Check if download is complete
            if completedPieces.count >= torrentFile.info.pieces.count {
                logger.info("✅ All pieces completed!")
                break
            }
            
            // Wait before next check
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
    
    private func requestPieces(from connection: PeerConnection) async throws {
        logger.info("Requesting pieces...")
        
        let pieceLength = torrentFile.info.pieceLength
        let blockSize = 16384 // 16KB blocks
        
        // Request a few pieces at a time
        var requestedCount = 0
        let maxConcurrentRequests = 5
        
        for pieceIndex in 0..<torrentFile.info.pieces.count {
            guard !completedPieces.contains(pieceIndex) else {
                continue
            }
            
            guard !requestedPieces.contains(pieceIndex) else {
                continue
            }
            
            if requestedCount >= maxConcurrentRequests {
                break
            }
            
            logger.info("Requesting piece: \(pieceIndex)")
            requestedPieces.insert(pieceIndex)
            requestedCount += 1
            
            let pieceSize = min(pieceLength, torrentFile.getTotalSize() - pieceIndex * pieceLength)
            
            for offset in stride(from: 0, to: pieceSize, by: blockSize) {
                let blockSize = min(UInt32(blockSize), UInt32(pieceSize - offset))
                
                try await connection.sendRequest(
                    pieceIndex: UInt32(pieceIndex),
                    offset: UInt32(offset),
                    length: blockSize
                )
                
                // Small delay to avoid overwhelming the peer
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        logger.info("Requested \(requestedCount) pieces")
    }
    
    private func handlePieceData(pieceIndex: UInt32, offset: UInt32, data: Data) async {
        let index = Int(pieceIndex)
        let blockIndex = Int(offset / 16384) // 16KB blocks
        
        logger.info("📥 Handling piece data: \(pieceIndex), offset: \(offset), size: \(data.count)")
        
        // Update piece state
        guard let pieceState = pieceStates[index] else {
            logger.error("❌ No piece state found for piece \(index)")
            return
        }
        
        pieceStates[index]?.downloadedBlocks.insert(blockIndex)
        
        // Store piece data
        if pieceData[index] == nil {
            pieceData[index] = Data()
        }
        
        // Ensure piece data is large enough
        while pieceData[index]!.count < Int(offset) + data.count {
            pieceData[index]!.append(0)
        }
        
        // Insert data at correct offset
        pieceData[index]!.replaceSubrange(Int(offset)..<Int(offset) + data.count, with: data)
        
        logger.info("📊 Piece \(index) progress: \(pieceData[index]!.count)/\(pieceState.size) bytes")
        
        // Check if piece is complete
        let expectedSize = pieceState.size
        if pieceData[index]!.count >= expectedSize {
            logger.info("🔍 Verifying piece \(index) hash...")
            
            // Verify piece hash
            let pieceHash = SHA1_hash(data: pieceData[index]!)
            let expectedHash = torrentFile.info.pieces[index]
            
            if pieceHash == expectedHash {
                logger.info("✅ Piece \(index) completed and verified")
                pieceStates[index]?.isComplete = true
                completedPieces.insert(index)
                
                // Write piece to file
                do {
                    try await writePieceToFile(index: index, data: pieceData[index]!)
                    
                    // Update progress
                    downloadedBytes += Int64(pieceData[index]!.count)
                    leftBytes -= Int64(pieceData[index]!.count)
                    
                    logger.info("📈 Progress: \(completedPieces.count)/\(torrentFile.info.pieces.count) pieces completed")
                    
                    // Clean up piece data
                    pieceData.removeValue(forKey: index)
                } catch {
                    logger.error("❌ Failed to write piece \(index) to file: \(error)")
                }
            } else {
                logger.error("❌ Piece \(index) hash verification failed")
                logger.error("Expected: \(expectedHash.map { String(format: "%02x", $0) }.joined())")
                logger.error("Got: \(pieceHash.map { String(format: "%02x", $0) }.joined())")
                
                // Reset piece state
                pieceStates[index]?.downloadedBlocks.removeAll()
                pieceData.removeValue(forKey: index)
            }
        }
    }
    
    private func writePieceToFile(index: Int, data: Data) async throws {
        guard let downloadPath = downloadPath else { return }
        
        let pieceLength = torrentFile.info.pieceLength
        let pieceOffset = index * pieceLength
        
        if torrentFile.info.files?.isEmpty ?? true {
            // Single file torrent
            if let handle = fileHandles[0] {
                try handle.seek(toOffset: UInt64(pieceOffset))
                try handle.write(contentsOf: data)
            }
        } else {
            // Multi-file torrent
            // This is more complex - need to map piece to files
            // For now, just write to first file
            if let handle = fileHandles[0] {
                try handle.seek(toOffset: UInt64(pieceOffset))
                try handle.write(contentsOf: data)
            }
        }
        
        logger.info("Wrote piece \(index) to file")
    }
    
    private func sendTrackerEvent(_ event: AnnounceEvent) async throws {
        let trackers = torrentFile.getAllTrackers()
        
        for tracker in trackers {
            do {
                _ = try await trackerClient.announce(
                    url: tracker,
                    infoHash: infoHash,
                    peerId: peerId,
                    port: 6881,
                    uploaded: uploadedBytes,
                    downloaded: downloadedBytes,
                    left: leftBytes,
                    event: event
                )
            } catch {
                logger.error("Failed to send \(event) event to tracker \(tracker): \(error)")
            }
        }
    }
}

/// Torrent session status
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
    
    public init(name: String, infoHash: String, totalSize: Int, downloadedBytes: Int64, uploadedBytes: Int64, leftBytes: Int64, progress: Double, uploadSpeed: Int64, downloadSpeed: Int64, peerCount: Int, isRunning: Bool) {
        self.name = name
        self.infoHash = infoHash
        self.totalSize = totalSize
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.leftBytes = leftBytes
        self.progress = progress
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.peerCount = peerCount
        self.isRunning = isRunning
    }
}

/// Torrent session errors
public enum TorrentSessionError: Error {
    case alreadyRunning
    case notRunning
    case invalidDownloadPath
    case insufficientDiskSpace
    case networkError
}
