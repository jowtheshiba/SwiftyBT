import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// BitTorrent tracker client
public class TrackerClient {
    private let logger: Logger
    
    public init() {
        self.logger = Logger(label: "SwiftyBT.Tracker")
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
        logger.info("Announcing to tracker: \(url)")
        guard let baseURL = URL(string: url) else {
            throw TrackerError.invalidURL
        }
        // BitTorrent spec: info_hash и peer_id должны быть вручную закодированы как raw bytes -> %XX
        let infoHashEncoded = infoHash.map { String(format: "%%%02x", $0) }.joined()
        let peerIdEncoded = peerId.map { String(format: "%%%02x", $0) }.joined()
        var urlString = baseURL.absoluteString
        urlString += baseURL.query != nil ? "&" : "?"
        urlString += "info_hash=\(infoHashEncoded)&peer_id=\(peerIdEncoded)&port=\(port)&uploaded=\(uploaded)&downloaded=\(downloaded)&left=\(left)&event=\(event.rawValue)&compact=1"
        logger.info("Final announce URL: \(urlString)")
        logger.info("Info hash (hex): \(infoHash.map { String(format: "%02x", $0) }.joined())")
        logger.info("Peer ID (hex): \(peerId.map { String(format: "%02x", $0) }.joined())")
        logger.info("Info hash (encoded): \(infoHashEncoded)")
        logger.info("Peer ID (encoded): \(peerIdEncoded)")
        guard let finalURL = URL(string: urlString) else {
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
        
        // Create URL with encoded parameters
        var urlString = baseURL.absoluteString
        urlString += baseURL.query != nil ? "&" : "?"
        
        for infoHash in infoHashes {
            let infoHashEncoded = infoHash.map { String(format: "%%%02x", $0) }.joined()
            urlString += "info_hash=\(infoHashEncoded)&"
        }
        
        // Remove trailing &
        if urlString.hasSuffix("&") {
            urlString.removeLast()
        }
        
        // Debug: print the scrape URL we're sending
        print("DEBUG: Sending scrape URL: \(urlString)")
        
        guard let finalURL = URL(string: urlString) else {
            throw TrackerError.invalidURL
        }
        
        return try await performScrapeRequest(url: finalURL)
    }
    
    private func performRequest(url: URL) async throws -> TrackerResponse {
        // Check if it's a UDP tracker
        if url.scheme?.lowercased() == "udp" {
            return try await performUDPRequest(url: url)
        } else {
            let data = try await performHTTPRequest(url: url)
            return try parseTrackerResponse(data)
        }
    }
    
    private func performUDPRequest(url: URL) async throws -> TrackerResponse {
        logger.info("🔗 Using UDP for tracker: \(url)")
        
        // For now, return empty response for UDP trackers
        // In a real implementation, you'd implement UDP protocol
        logger.warning("⚠️ UDP tracker support not implemented yet")
        
        return TrackerResponse(
            interval: 1800,
            minInterval: nil,
            complete: nil,
            incomplete: nil,
            peers: [],
            warning: "UDP not supported"
        )
    }
    
    private func performScrapeRequest(url: URL) async throws -> ScrapeResponse {
        let data = try await performHTTPRequest(url: url)
        return try parseScrapeResponse(data)
    }
    
    private func performHTTPRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Transmission/3.00", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("close", forHTTPHeaderField: "Connection")
        
        // Set timeout to 30 seconds
        request.timeoutInterval = 30.0
        
        logger.debug("Sending request to: \(url)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unable to decode error response"
                logger.error("HTTP Error \(httpResponse.statusCode): \(errorBody)")
                throw TrackerError.httpError(statusCode: httpResponse.statusCode, responseBody: errorBody)
            }
        }
        
        return data
    }
    
    private func parseTrackerResponse(_ data: Data) throws -> TrackerResponse {
        let bencodeValue = try Bencode.parse(data)
        
        guard case .dictionary(let dict) = bencodeValue else {
            throw TrackerError.invalidResponse
        }
        
        // Parse failure reason if present
        if let failureReason = dict["failure reason"],
           case .string(let reason) = failureReason {
            // Try to get more details from the response
            let responseDetails = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw TrackerError.trackerFailure(reason: reason, responseDetails: responseDetails)
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
            // Try to get more details from the response
            let responseDetails = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw TrackerError.trackerFailure(reason: reason, responseDetails: responseDetails)
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
    case httpError(statusCode: Int, responseBody: String)
    case trackerFailure(reason: String, responseDetails: String)
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