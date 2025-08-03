import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
import NIOPosix
import Logging

/// BitTorrent tracker client
public class TrackerClient {
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    
    public init(eventLoopGroup: EventLoopGroup? = nil) {
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "SwiftyBT.Tracker")
    }
    
    deinit {
        if eventLoopGroup is MultiThreadedEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
    
    /// Announce to tracker and get peer list
    /// - Parameters:
    ///   - url: Tracker URL
    ///   - infoHash: Info hash of the torrent
    ///   - peerId: Client peer ID
    ///   - port: Port for incoming connections
    ///   - uploaded: Bytes uploaded
    ///   - downloaded: Bytes downloaded
    ///   - left: Bytes left to download
    ///   - event: Announce event type
    /// - Returns: Tracker response with peer list
    /// - Throws: TrackerError if request fails
    public func announce(
        url: String,
        infoHash: Data,
        peerId: Data,
        port: UInt16,
        uploaded: Int64 = 0,
        downloaded: Int64 = 0,
        left: Int64,
        event: AnnounceEvent = .started
    ) async throws -> TrackerResponse {
        guard let url = URL(string: url) else {
            throw TrackerError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        
        // Add required parameters
        queryItems.append(URLQueryItem(name: "info_hash", value: infoHash.base64EncodedString()))
        queryItems.append(URLQueryItem(name: "peer_id", value: peerId.base64EncodedString()))
        queryItems.append(URLQueryItem(name: "port", value: String(port)))
        queryItems.append(URLQueryItem(name: "uploaded", value: String(uploaded)))
        queryItems.append(URLQueryItem(name: "downloaded", value: String(downloaded)))
        queryItems.append(URLQueryItem(name: "left", value: String(left)))
        queryItems.append(URLQueryItem(name: "event", value: event.rawValue))
        queryItems.append(URLQueryItem(name: "compact", value: "1"))
        
        components.queryItems = queryItems
        
        guard let finalURL = components.url else {
            throw TrackerError.invalidURL
        }
        
        return try await performRequest(url: finalURL)
    }
    
    /// Scrape tracker for torrent statistics
    /// - Parameters:
    ///   - url: Tracker URL
    ///   - infoHashes: Array of info hashes to scrape
    /// - Returns: Scrape response with statistics
    /// - Throws: TrackerError if request fails
    public func scrape(url: String, infoHashes: [Data]) async throws -> ScrapeResponse {
        guard let baseURL = URL(string: url) else {
            throw TrackerError.invalidURL
        }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        
        // Add info hashes
        for infoHash in infoHashes {
            queryItems.append(URLQueryItem(name: "info_hash", value: infoHash.base64EncodedString()))
        }
        
        components.queryItems = queryItems
        
        guard let finalURL = components.url else {
            throw TrackerError.invalidURL
        }
        
        return try await performScrapeRequest(url: finalURL)
    }
    
    private func performRequest(url: URL) async throws -> TrackerResponse {
        let request = URLRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TrackerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try parseTrackerResponse(data)
    }
    
    private func performScrapeRequest(url: URL) async throws -> ScrapeResponse {
        let request = URLRequest(url: url)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrackerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TrackerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try parseScrapeResponse(data)
    }
    
    private func parseTrackerResponse(_ data: Data) throws -> TrackerResponse {
        let bencodeValue = try Bencode.parse(data)
        
        guard case .dictionary(let dict) = bencodeValue else {
            throw TrackerError.invalidResponse
        }
        
        // Parse failure reason if present
        if let failureReason = dict["failure reason"],
           case .string(let reason) = failureReason {
            throw TrackerError.trackerFailure(reason: reason)
        }
        
        // Parse warning message if present
        let warning: String?
        if let value = dict["warning message"], case .string(let warningStr) = value {
            warning = warningStr
        } else {
            warning = nil
        }
        
        // Parse interval
        guard let intervalValue = dict["interval"],
              case .integer(let interval) = intervalValue else {
            throw TrackerError.missingInterval
        }
        
        // Parse min interval
        let minInterval: Int?
        if let value = dict["min interval"], case .integer(let interval) = value {
            minInterval = Int(interval)
        } else {
            minInterval = nil
        }
        
        // Parse complete count
        let complete: Int?
        if let value = dict["complete"], case .integer(let count) = value {
            complete = Int(count)
        } else {
            complete = nil
        }
        
        // Parse incomplete count
        let incomplete: Int?
        if let value = dict["incomplete"], case .integer(let count) = value {
            incomplete = Int(count)
        } else {
            incomplete = nil
        }
        
        // Parse peers
        let peers = try parsePeers(dict["peers"])
        
        return TrackerResponse(
            interval: Int(interval),
            minInterval: minInterval,
            complete: complete,
            incomplete: incomplete,
            peers: peers,
            warning: warning
        )
    }
    
    private func parseScrapeResponse(_ data: Data) throws -> ScrapeResponse {
        let bencodeValue = try Bencode.parse(data)
        
        guard case .dictionary(let dict) = bencodeValue else {
            throw TrackerError.invalidResponse
        }
        
        // Parse failure reason if present
        if let failureReason = dict["failure reason"],
           case .string(let reason) = failureReason {
            throw TrackerError.trackerFailure(reason: reason)
        }
        
        var files: [Data: ScrapeFileInfo] = [:]
        
        for (key, value) in dict {
            guard case .dictionary(let fileDict) = value else { continue }
            
            let complete = fileDict["complete"].flatMap { value in
                guard case .integer(let count) = value else { return nil }
                return Int(count)
            } ?? 0
            
            let downloaded = fileDict["downloaded"].flatMap { value in
                guard case .integer(let count) = value else { return nil }
                return Int(count)
            } ?? 0
            
            let incomplete = fileDict["incomplete"].flatMap { value in
                guard case .integer(let count) = value else { return nil }
                return Int(count)
            } ?? 0
            
            let name: String?
            if let value = fileDict["name"], case .string(let nameStr) = value {
                name = nameStr
            } else {
                name = nil
            }
            
            // Convert hex string to data for key
            if let keyData = Data(hexString: key) {
                files[keyData] = ScrapeFileInfo(
                    complete: complete,
                    downloaded: downloaded,
                    incomplete: incomplete,
                    name: name
                )
            }
        }
        
        return ScrapeResponse(files: files)
    }
    
    private func parsePeers(_ peersValue: Bencode.Value?) throws -> [Peer] {
        guard let peersValue = peersValue else { return [] }
        
        switch peersValue {
        case .string(let peersString):
            // Compact format: 6 bytes per peer (4 bytes IP + 2 bytes port)
            return try parseCompactPeers(peersString)
        case .list(let peersList):
            // Dictionary format
            return try parseDictionaryPeers(peersList)
        default:
            return []
        }
    }
    
    private func parseCompactPeers(_ peersString: String) throws -> [Peer] {
        let data = Data(peersString.utf8)
        guard data.count % 6 == 0 else {
            throw TrackerError.invalidPeerFormat
        }
        
        var peers: [Peer] = []
        
        for i in stride(from: 0, to: data.count, by: 6) {
            let peerData = data[i..<(i + 6)]
            
            // Extract IP address (first 4 bytes)
            let ipBytes = Array(peerData.prefix(4))
            let ip = ipBytes.map { String($0) }.joined(separator: ".")
            
            // Extract port (last 2 bytes, big endian)
            let portBytes = Array(peerData.suffix(2))
            let port = UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])
            
            peers.append(Peer(address: ip, port: port))
        }
        
        return peers
    }
    
    private func parseDictionaryPeers(_ peersList: [Bencode.Value]) throws -> [Peer] {
        var peers: [Peer] = []
        
        for peerValue in peersList {
            guard case .dictionary(let peerDict) = peerValue else { continue }
            
            guard let ipValue = peerDict["ip"],
                  case .string(let ip) = ipValue else { continue }
            
            guard let portValue = peerDict["port"],
                  case .integer(let port) = portValue else { continue }
            
            let peerId: Data?
            if let value = peerDict["peer id"], case .string(let id) = value {
                peerId = Data(id.utf8)
            } else {
                peerId = nil
            }
            
            peers.append(Peer(
                address: ip,
                port: UInt16(port),
                peerId: peerId
            ))
        }
        
        return peers
    }
}

/// Tracker announce event types
public enum AnnounceEvent: String {
    case started = "started"
    case stopped = "stopped"
    case completed = "completed"
    case empty = ""
}

/// Tracker response with peer information
public struct TrackerResponse {
    public let interval: Int
    public let minInterval: Int?
    public let complete: Int?
    public let incomplete: Int?
    public let peers: [Peer]
    public let warning: String?
    
    public init(interval: Int, minInterval: Int? = nil, complete: Int? = nil, incomplete: Int? = nil, peers: [Peer], warning: String? = nil) {
        self.interval = interval
        self.minInterval = minInterval
        self.complete = complete
        self.incomplete = incomplete
        self.peers = peers
        self.warning = warning
    }
}

/// Scrape response with torrent statistics
public struct ScrapeResponse {
    public let files: [Data: ScrapeFileInfo]
    
    public init(files: [Data: ScrapeFileInfo]) {
        self.files = files
    }
}

/// File information from scrape response
public struct ScrapeFileInfo {
    public let complete: Int
    public let downloaded: Int
    public let incomplete: Int
    public let name: String?
    
    public init(complete: Int, downloaded: Int, incomplete: Int, name: String? = nil) {
        self.complete = complete
        self.downloaded = downloaded
        self.incomplete = incomplete
        self.name = name
    }
}

/// Peer information
public struct Peer {
    public let address: String
    public let port: UInt16
    public let peerId: Data?
    
    public init(address: String, port: UInt16, peerId: Data? = nil) {
        self.address = address
        self.port = port
        self.peerId = peerId
    }
}

/// Tracker client errors
public enum TrackerError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case trackerFailure(reason: String)
    case missingInterval
    case invalidPeerFormat
}

// MARK: - Data Extension
private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        let bytes = stride(from: 0, to: chars.count, by: 2).map {
            String(chars[$0..<Swift.min($0 + 2, chars.count)])
        }
        
        self = Data(bytes.compactMap { UInt8($0, radix: 16) })
    }
} 
