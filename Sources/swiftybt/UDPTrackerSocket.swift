import Foundation
import Logging

/// UDP tracker socket for BitTorrent tracker communication
public class UDPTrackerSocket {
    private let logger: Logger
    private let udpSocket: UDPSocket
    
    public init() {
        self.logger = Logger(label: "SwiftyBT.UDPTrackerSocket")
        self.udpSocket = UDPSocket(timeout: 10.0)
    }
    
    /// Perform UDP announce to tracker
    /// - Parameters:
    ///   - host: Tracker host
    ///   - port: Tracker port
    ///   - infoHash: Info hash of the torrent
    ///   - peerId: Client peer ID
    ///   - port: Client port
    ///   - uploaded: Bytes uploaded
    ///   - downloaded: Bytes downloaded
    ///   - left: Bytes left to download
    ///   - event: Tracker event
    /// - Returns: Tracker response
    /// - Throws: TrackerError if request fails
    public func performUDPAnnounce(
        host: String,
        port: UInt16,
        infoHash: Data,
        peerId: Data,
        port clientPort: UInt16,
        uploaded: UInt64,
        downloaded: UInt64,
        left: UInt64,
        event: TrackerEvent
    ) async throws -> TrackerResponse {
        logger.info("Performing UDP announce to \(host):\(port)")
        
        // Step 1: Connect to tracker
        let connectionId = try await performUDPConnect(host: host, port: port)
        logger.debug("Got connection ID: \(connectionId)")
        
        // Step 2: Announce to tracker
        let announceData = createAnnounceRequest(
            connectionId: connectionId,
            infoHash: infoHash,
            peerId: peerId,
            port: clientPort,
            uploaded: uploaded,
            downloaded: downloaded,
            left: left,
            event: event
        )
        
        let responseData = try await udpSocket.sendAndReceive(announceData, to: host, port: port)
        
        return try parseUDPAnnounceResponse(responseData)
    }
    
    /// Perform UDP connect to get connection ID
    /// - Parameters:
    ///   - host: Tracker host
    ///   - port: Tracker port
    /// - Returns: Connection ID
    /// - Throws: TrackerError if connect fails
    private func performUDPConnect(host: String, port: UInt16) async throws -> UInt64 {
        logger.debug("Connecting to UDP tracker \(host):\(port)")
        
        let connectData = createConnectRequest()
        let responseData = try await udpSocket.sendAndReceive(connectData, to: host, port: port)
        
        return try parseUDPConnectResponse(responseData)
    }
    
    /// Create UDP connect request
    /// - Returns: Connect request data
    private func createConnectRequest() -> Data {
        var request = Data()
        
        // Protocol ID (magic constant)
        request.append(contentsOf: [0x00, 0x00, 0x04, 0x17, 0x27, 0x10, 0x19, 0x80])
        
        // Action (0 = connect)
        request.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Data($0) })
        
        // Transaction ID (random)
        let transactionId = UInt32.random(in: 0...UInt32.max)
        request.append(contentsOf: withUnsafeBytes(of: transactionId.bigEndian) { Data($0) })
        
        return request
    }
    
    /// Create UDP announce request
    /// - Parameters:
    ///   - connectionId: Connection ID from connect response
    ///   - infoHash: Info hash of the torrent
    ///   - peerId: Client peer ID
    ///   - port: Client port
    ///   - uploaded: Bytes uploaded
    ///   - downloaded: Bytes downloaded
    ///   - left: Bytes left to download
    ///   - event: Tracker event
    /// - Returns: Announce request data
    private func createAnnounceRequest(
        connectionId: UInt64,
        infoHash: Data,
        peerId: Data,
        port: UInt16,
        uploaded: UInt64,
        downloaded: UInt64,
        left: UInt64,
        event: TrackerEvent
    ) -> Data {
        var request = Data()
        
        // Connection ID
        request.append(contentsOf: withUnsafeBytes(of: connectionId.bigEndian) { Data($0) })
        
        // Action (1 = announce)
        request.append(contentsOf: withUnsafeBytes(of: UInt32(1).bigEndian) { Data($0) })
        
        // Transaction ID (random)
        let transactionId = UInt32.random(in: 0...UInt32.max)
        request.append(contentsOf: withUnsafeBytes(of: transactionId.bigEndian) { Data($0) })
        
        // Info hash (20 bytes)
        request.append(infoHash)
        
        // Peer ID (20 bytes)
        request.append(peerId)
        
        // Downloaded (8 bytes)
        request.append(contentsOf: withUnsafeBytes(of: downloaded.bigEndian) { Data($0) })
        
        // Left (8 bytes)
        request.append(contentsOf: withUnsafeBytes(of: left.bigEndian) { Data($0) })
        
        // Uploaded (8 bytes)
        request.append(contentsOf: withUnsafeBytes(of: uploaded.bigEndian) { Data($0) })
        
        // Event (4 bytes)
        request.append(contentsOf: withUnsafeBytes(of: UInt32(event.rawValue).bigEndian) { Data($0) })
        
        // IP address (4 bytes, 0 = use sender's address)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        // Key (4 bytes, random)
        let key = UInt32.random(in: 0...UInt32.max)
        request.append(contentsOf: withUnsafeBytes(of: key.bigEndian) { Data($0) })
        
        // Num want (-1 = default)
        request.append(contentsOf: withUnsafeBytes(of: Int32(-1).bigEndian) { Data($0) })
        
        // Port (2 bytes)
        request.append(contentsOf: withUnsafeBytes(of: port.bigEndian) { Data($0) })
        
        return request
    }
    
    /// Parse UDP connect response
    /// - Parameter data: Response data
    /// - Returns: Connection ID
    /// - Throws: TrackerError if parsing fails
    private func parseUDPConnectResponse(_ data: Data) throws -> UInt64 {
        guard data.count >= 16 else {
            throw TrackerError.invalidResponse
        }
        
        // Parse action (should be 0)
        let action = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard action == 0 else {
            throw TrackerError.invalidResponse
        }
        
        // Parse connection ID
        let connectionId = data[4..<12].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        
        return connectionId
    }
    
    /// Parse UDP announce response
    /// - Parameter data: Response data
    /// - Returns: Tracker response
    /// - Throws: TrackerError if parsing fails
    private func parseUDPAnnounceResponse(_ data: Data) throws -> TrackerResponse {
        guard data.count >= 20 else {
            throw TrackerError.invalidResponse
        }
        
        // Parse action (should be 1)
        let action = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard action == 1 else {
            throw TrackerError.invalidResponse
        }
        
        // Parse interval
        let interval = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        // Parse leechers
        let leechers = data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        // Parse seeders
        let seeders = data[16..<20].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        // Parse peers (6 bytes each: 4 bytes IP + 2 bytes port)
        var peers: [Peer] = []
        let peerData = data.dropFirst(20)
        
        for i in stride(from: 0, to: peerData.count, by: 6) {
            guard i + 6 <= peerData.count else { break }
            
            let peerBytes = Array(peerData[i..<i+6])
            
            // Extract IP address
            let ip = peerBytes[0..<4].map { String($0) }.joined(separator: ".")
            
            // Extract port (big endian)
            let port = UInt16(peerBytes[4]) << 8 | UInt16(peerBytes[5])
            
            peers.append(Peer(address: ip, port: port))
        }
        
        logger.info("UDP announce response: \(peers.count) peers, \(seeders) seeders, \(leechers) leechers")
        
        return TrackerResponse(
            interval: Int(interval),
            minInterval: nil,
            complete: Int(seeders),
            incomplete: Int(leechers),
            peers: peers,
            warning: nil
        )
    }
}

 