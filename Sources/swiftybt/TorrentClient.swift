import Foundation
import NIOCore
import NIOPosix
import Logging

/// Main BitTorrent client
public class TorrentClient {
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    private let trackerClient: TrackerClient
    private let peerWireClient: PeerWireClient
    
    private var activeTorrents: [String: TorrentSession] = [:]
    
    public init(eventLoopGroup: EventLoopGroup? = nil) {
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "SwiftyBT.TorrentClient")
        self.trackerClient = TrackerClient(eventLoopGroup: self.eventLoopGroup)
        self.peerWireClient = PeerWireClient(eventLoopGroup: self.eventLoopGroup)
    }
    
    deinit {
        if eventLoopGroup is MultiThreadedEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
    
    /// Load torrent from file
    /// - Parameter url: URL to .torrent file
    /// - Returns: Torrent session
    /// - Throws: TorrentFileError if parsing fails
    public func loadTorrent(from url: URL) throws -> TorrentSession {
        let torrentFile = try TorrentFile.parse(from: url)
        let infoHash = try torrentFile.getInfoHash()
        let infoHashHex = try torrentFile.getInfoHashHex()
        
        let session = TorrentSession(
            torrentFile: torrentFile,
            infoHash: infoHash,
            infoHashHex: infoHashHex,
            trackerClient: trackerClient,
            peerWireClient: peerWireClient,
            eventLoopGroup: eventLoopGroup
        )
        
        activeTorrents[infoHashHex] = session
        return session
    }
    
    /// Load torrent from data
    /// - Parameter data: Raw torrent file data
    /// - Returns: Torrent session
    /// - Throws: TorrentFileError if parsing fails
    public func loadTorrent(from data: Data) throws -> TorrentSession {
        let torrentFile = try TorrentFile.parse(data)
        let infoHash = try torrentFile.getInfoHash()
        let infoHashHex = try torrentFile.getInfoHashHex()
        
        let session = TorrentSession(
            torrentFile: torrentFile,
            infoHash: infoHash,
            infoHashHex: infoHashHex,
            trackerClient: trackerClient,
            peerWireClient: peerWireClient,
            eventLoopGroup: eventLoopGroup
        )
        
        activeTorrents[infoHashHex] = session
        return session
    }
    
    /// Get active torrent session by info hash
    /// - Parameter infoHashHex: Info hash as hex string
    /// - Returns: Torrent session if exists
    public func getTorrentSession(infoHashHex: String) -> TorrentSession? {
        return activeTorrents[infoHashHex]
    }
    
    /// Remove torrent session
    /// - Parameter infoHashHex: Info hash as hex string
    public func removeTorrentSession(infoHashHex: String) {
        activeTorrents.removeValue(forKey: infoHashHex)
    }
    
    /// Get all active torrent sessions
    /// - Returns: Array of active torrent sessions
    public func getAllTorrentSessions() -> [TorrentSession] {
        return Array(activeTorrents.values)
    }
}

/// Torrent session for managing a single torrent
public class TorrentSession {
    public let torrentFile: TorrentFile
    public let infoHash: Data
    public let infoHashHex: String
    
    private let trackerClient: TrackerClient
    private let peerWireClient: PeerWireClient
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    
    private var peerConnections: [String: PeerConnection] = [:]
    private var peerId: Data
    private var isRunning = false
    
    public var downloadPath: String?
    public var uploadSpeed: Int64 = 0
    public var downloadSpeed: Int64 = 0
    public var uploadedBytes: Int64 = 0
    public var downloadedBytes: Int64 = 0
    public var leftBytes: Int64
    
    public init(
        torrentFile: TorrentFile,
        infoHash: Data,
        infoHashHex: String,
        trackerClient: TrackerClient,
        peerWireClient: PeerWireClient,
        eventLoopGroup: EventLoopGroup
    ) {
        self.torrentFile = torrentFile
        self.infoHash = infoHash
        self.infoHashHex = infoHashHex
        self.trackerClient = trackerClient
        self.peerWireClient = peerWireClient
        self.eventLoopGroup = eventLoopGroup
                    self.logger = Logger(label: "SwiftyBT.TorrentSession.\(infoHashHex.prefix(8))")
        
        // Generate random peer ID
        self.peerId = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        
        // Calculate total size
        self.leftBytes = Int64(torrentFile.getTotalSize())
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
        
        // Start tracker communication
        try await startTrackerCommunication()
        
        // Start peer discovery
        try await startPeerDiscovery()
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
        
        // Send stopped event to trackers
        try? await sendTrackerEvent(.stopped)
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
        
        for tracker in trackers {
            do {
                let response = try await trackerClient.announce(
                    url: tracker,
                    infoHash: infoHash,
                    peerId: peerId,
                    port: 6881, // Default BitTorrent port
                    uploaded: uploadedBytes,
                    downloaded: downloadedBytes,
                    left: leftBytes,
                    event: .started
                )
                
                logger.info("Tracker \(tracker) returned \(response.peers.count) peers")
                
                // Connect to peers
                for peer in response.peers {
                    try await connectToPeer(peer)
                }
                
            } catch {
                logger.error("Failed to announce to tracker \(tracker): \(error)")
            }
        }
    }
    
    private func startPeerDiscovery() async throws {
        // This would typically involve DHT, PEX, and other peer discovery methods
        // For now, we'll just use trackers
        logger.info("Peer discovery started")
    }
    
    private func connectToPeer(_ peer: Peer) async throws {
        let peerKey = "\(peer.address):\(peer.port)"
        
        guard peerConnections[peerKey] == nil else {
            return // Already connected
        }
        
        do {
            let connection = try await peerWireClient.connect(
                to: peer.address,
                port: peer.port,
                infoHash: infoHash,
                peerId: peerId
            )
            
            peerConnections[peerKey] = connection
            logger.info("Connected to peer: \(peerKey)")
            
            // Start peer communication
            try await startPeerCommunication(connection)
            
        } catch {
            logger.error("Failed to connect to peer \(peerKey): \(error)")
        }
    }
    
    private func startPeerCommunication(_ connection: PeerConnection) async throws {
        // Send interested message
        try await connection.sendInterested()
        
        // Send our bitfield (empty for now)
        let bitfield = Array(repeating: false, count: torrentFile.info.pieces.count)
        try await connection.sendBitfield(bitfield)
        
        // Start piece requests if peer is not choked
        if !(await connection.isPeerChoked()) {
            try await requestPieces(from: connection)
        }
    }
    
    private func requestPieces(from connection: PeerConnection) async throws {
        // Simple piece requesting strategy
        // In a real implementation, this would be more sophisticated
        let pieceLength = torrentFile.info.pieceLength
        let blockSize = 16384 // 16KB blocks
        
        for pieceIndex in 0..<torrentFile.info.pieces.count {
            let pieceSize = min(pieceLength, torrentFile.getTotalSize() - pieceIndex * pieceLength)
            
            for offset in stride(from: 0, to: pieceSize, by: blockSize) {
                let blockSize = min(UInt32(blockSize), UInt32(pieceSize - offset))
                
                try await connection.sendRequest(
                    pieceIndex: UInt32(pieceIndex),
                    offset: UInt32(offset),
                    length: blockSize
                )
            }
        }
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