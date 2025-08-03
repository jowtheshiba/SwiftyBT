import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOPosix
import Logging

/// Main BitTorrent client
public class TorrentClient {
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    private let trackerClient: TrackerClient
    private let extendedTrackerClient: ExtendedTrackerClient
    private let dhtClient: DHTClient
    private let pexClient: PEXClient
    private let peerWireClient: PeerWireClient
    
    private var activeTorrents: [String: TorrentSession] = [:]
    
    public init(eventLoopGroup: EventLoopGroup? = nil, enableDHT: Bool = true, enablePEX: Bool = true) {
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "SwiftyBT.TorrentClient")
        self.trackerClient = TrackerClient()
        self.extendedTrackerClient = ExtendedTrackerClient()
        self.dhtClient = DHTClient()
        self.pexClient = PEXClient()
        self.peerWireClient = PeerWireClient(eventLoopGroup: self.eventLoopGroup)
        
        // Start DHT if enabled
        if enableDHT {
            Task {
                do {
                    try await dhtClient.start()
                    logger.info("DHT client started successfully")
                } catch {
                    logger.error("Failed to start DHT client: \(error)")
                }
            }
        }
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
            extendedTrackerClient: extendedTrackerClient,
            dhtClient: dhtClient,
            pexClient: pexClient,
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
            extendedTrackerClient: extendedTrackerClient,
            dhtClient: dhtClient,
            pexClient: pexClient,
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
