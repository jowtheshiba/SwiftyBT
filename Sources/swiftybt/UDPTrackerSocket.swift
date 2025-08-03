import Foundation
import Logging

/// UDP tracker socket for BitTorrent tracker communication
public class UDPTrackerSocket {
    private let logger: Logger
    private let udpSocket: UDPSocket
    
    public init() {
        self.logger = Logger(label: "SwiftyBT.UDPTrackerSocket")
        self.udpSocket = UDPSocket(timeout: 30.0)
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
        let (connectionId, connectTransactionId) = try await performUDPConnect(host: host, port: port)
        logger.debug("Got connection ID: \(connectionId), transaction ID: \(connectTransactionId)")
        
        // Step 2: Announce to tracker
        let (announceData, announceTransactionId) = createAnnounceRequest(
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
        
        return try parseUDPAnnounceResponse(responseData, expectedTransactionId: announceTransactionId)
    }
    
    /// Perform UDP connect to get connection ID
    /// - Parameters:
    ///   - host: Tracker host
    ///   - port: Tracker port
    /// - Returns: Connection ID and transaction ID
    /// - Throws: TrackerError if connect fails
    private func performUDPConnect(host: String, port: UInt16) async throws -> (UInt64, UInt32) {
        logger.debug("Connecting to UDP tracker \(host):\(port)")
        
        let (connectData, transactionId) = createConnectRequest()
        let responseData = try await udpSocket.sendAndReceive(connectData, to: host, port: port)
        
        let connectionId = try parseUDPConnectResponse(responseData, expectedTransactionId: transactionId)
        return (connectionId, transactionId)
    }
    
    /// Create UDP connect request
    /// - Returns: Connect request data and transaction ID
    private func createConnectRequest() -> (Data, UInt32) {
        var request = Data()
        
        // Protocol ID (magic constant)
        request.append(contentsOf: [0x00, 0x00, 0x04, 0x17, 0x27, 0x10, 0x19, 0x80])
        
        // Action (0 = connect)
        request.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Data($0) })
        
        // Transaction ID (random)
        let transactionId = UInt32.random(in: 0...UInt32.max)
        request.append(contentsOf: withUnsafeBytes(of: transactionId.bigEndian) { Data($0) })
        
        return (request, transactionId)
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
    /// - Returns: Announce request data and transaction ID
    private func createAnnounceRequest(
        connectionId: UInt64,
        infoHash: Data,
        peerId: Data,
        port: UInt16,
        uploaded: UInt64,
        downloaded: UInt64,
        left: UInt64,
        event: TrackerEvent
    ) -> (Data, UInt32) {
        var request = Data()
        
        // Connection ID - correctly handle big-endian
        let connectionIdBytes = withUnsafeBytes(of: connectionId.bigEndian) { Data($0) }
        request.append(connectionIdBytes)
        
        // Action (1 = announce) - correctly handle big-endian
        let actionBytes = withUnsafeBytes(of: UInt32(1).bigEndian) { Data($0) }
        request.append(actionBytes)
        
        // Transaction ID (random) - correctly handle big-endian
        let transactionId = UInt32.random(in: 0...UInt32.max)
        let transactionIdBytes = withUnsafeBytes(of: transactionId.bigEndian) { Data($0) }
        request.append(transactionIdBytes)
        
        // Info hash (20 bytes)
        request.append(infoHash)
        
        // Peer ID (20 bytes)
        request.append(peerId)
        
        // Downloaded (8 bytes) - correctly handle big-endian
        let downloadedBytes = withUnsafeBytes(of: downloaded.bigEndian) { Data($0) }
        request.append(downloadedBytes)
        
        // Left (8 bytes) - correctly handle big-endian
        let leftBytes = withUnsafeBytes(of: left.bigEndian) { Data($0) }
        request.append(leftBytes)
        
        // Uploaded (8 bytes) - correctly handle big-endian
        let uploadedBytes = withUnsafeBytes(of: uploaded.bigEndian) { Data($0) }
        request.append(uploadedBytes)
        
        // Event (4 bytes) - correctly handle big-endian
        let eventBytes = withUnsafeBytes(of: UInt32(event.rawValue).bigEndian) { Data($0) }
        request.append(eventBytes)
        
        // IP address (4 bytes, 0 = use sender's address)
        request.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        
        // Key (4 bytes, random) - correctly handle big-endian
        let key = UInt32.random(in: 0...UInt32.max)
        let keyBytes = withUnsafeBytes(of: key.bigEndian) { Data($0) }
        request.append(keyBytes)
        
        // Num want (-1 = default) - correctly handle big-endian
        let numWantBytes = withUnsafeBytes(of: Int32(-1).bigEndian) { Data($0) }
        request.append(numWantBytes)
        
        // Port (2 bytes) - correctly handle big-endian
        let portBytes = withUnsafeBytes(of: port.bigEndian) { Data($0) }
        request.append(portBytes)
        
        logger.debug("UDP announce request size: \(request.count) bytes")
        logger.debug("UDP announce request connection ID: \(connectionId)")
        logger.debug("UDP announce request transaction ID: \(transactionId)")
        
        return (request, transactionId)
    }
    
    /// Parse UDP connect response
    /// - Parameter data: Response data
    /// - Parameter expectedTransactionId: Expected transaction ID
    /// - Returns: Connection ID
    /// - Throws: TrackerError if parsing fails
    private func parseUDPConnectResponse(_ data: Data, expectedTransactionId: UInt32) throws -> UInt64 {
        guard data.count >= 16 else {
            throw TrackerError.invalidResponse
        }
        
        // Parse action (should be 0) - correctly handle big-endian
        let actionBytes = Array(data[0..<4])
        let action = UInt32(actionBytes[0]) << 24 | UInt32(actionBytes[1]) << 16 | UInt32(actionBytes[2]) << 8 | UInt32(actionBytes[3])
        logger.debug("UDP connect response action: \(action), expected: 0")
        guard action == 0 else {
            logger.error("UDP connect response has wrong action: \(action), expected: 0")
            throw TrackerError.invalidResponse
        }
        
        // Parse transaction ID - correctly handle big-endian
        let transactionIdBytes = Array(data[4..<8])
        let transactionId = UInt32(transactionIdBytes[0]) << 24 | UInt32(transactionIdBytes[1]) << 16 | UInt32(transactionIdBytes[2]) << 8 | UInt32(transactionIdBytes[3])
        logger.debug("UDP connect response transaction ID: \(transactionId), expected: \(expectedTransactionId)")
        guard transactionId == expectedTransactionId else {
            logger.error("UDP connect response has wrong transaction ID: \(transactionId), expected: \(expectedTransactionId)")
            throw TrackerError.invalidResponse
        }
        
        // Parse connection ID - correctly handle big-endian
        let connectionIdBytes = Array(data[8..<16])
        let connectionId = UInt64(connectionIdBytes[0]) << 56 | UInt64(connectionIdBytes[1]) << 48 | UInt64(connectionIdBytes[2]) << 40 | UInt64(connectionIdBytes[3]) << 32 | UInt64(connectionIdBytes[4]) << 24 | UInt64(connectionIdBytes[5]) << 16 | UInt64(connectionIdBytes[6]) << 8 | UInt64(connectionIdBytes[7])
        
        logger.debug("UDP connect response connection ID: \(connectionId)")
        
        return connectionId
    }
    
    /// Parse UDP announce response
    /// - Parameter data: Response data
    /// - Parameter expectedTransactionId: Expected transaction ID
    /// - Returns: Tracker response
    /// - Throws: TrackerError if parsing fails
    private func parseUDPAnnounceResponse(_ data: Data, expectedTransactionId: UInt32) throws -> TrackerResponse {
        guard data.count >= 20 else {
            logger.error("UDP announce response too short: \(data.count) bytes")
            throw TrackerError.invalidResponse
        }
        
        // Parse action (should be 1) - correctly handle big-endian
        let actionBytes = Array(data[0..<4])
        let action = UInt32(actionBytes[0]) << 24 | UInt32(actionBytes[1]) << 16 | UInt32(actionBytes[2]) << 8 | UInt32(actionBytes[3])
        
        logger.debug("UDP announce response action: \(action), expected: 1")
        
        guard action == 1 else {
            if action == 3 {
                // Parse error message
                let errorData = data.dropFirst(8) // Skip action and transaction ID
                if let errorMessage = String(data: errorData, encoding: .utf8) {
                    logger.error("UDP tracker error: \(errorMessage)")
                    throw TrackerError.trackerFailure(reason: errorMessage, responseDetails: String(data: data, encoding: .utf8) ?? "Unknown error")
                } else {
                    logger.error("UDP tracker error (unable to decode message)")
                    throw TrackerError.trackerFailure(reason: "Unknown UDP tracker error", responseDetails: String(data: data, encoding: .utf8) ?? "Unknown error")
                }
            } else {
                logger.error("UDP announce response has wrong action: \(action), expected: 1")
                throw TrackerError.invalidResponse
            }
        }
        
        // Parse transaction ID - correctly handle big-endian
        let transactionIdBytes = Array(data[4..<8])
        let transactionId = UInt32(transactionIdBytes[0]) << 24 | UInt32(transactionIdBytes[1]) << 16 | UInt32(transactionIdBytes[2]) << 8 | UInt32(transactionIdBytes[3])
        logger.debug("UDP announce response transaction ID: \(transactionId), expected: \(expectedTransactionId)")
        guard transactionId == expectedTransactionId else {
            logger.error("UDP announce response has wrong transaction ID: \(transactionId), expected: \(expectedTransactionId)")
            throw TrackerError.invalidResponse
        }
        
        // Parse interval - correctly handle big-endian
        let intervalBytes = Array(data[8..<12])
        let interval = UInt32(intervalBytes[0]) << 24 | UInt32(intervalBytes[1]) << 16 | UInt32(intervalBytes[2]) << 8 | UInt32(intervalBytes[3])
        
        // Parse leechers - correctly handle big-endian
        let leechersBytes = Array(data[12..<16])
        let leechers = UInt32(leechersBytes[0]) << 24 | UInt32(leechersBytes[1]) << 16 | UInt32(leechersBytes[2]) << 8 | UInt32(leechersBytes[3])
        
        // Parse seeders - correctly handle big-endian
        let seedersBytes = Array(data[16..<20])
        let seeders = UInt32(seedersBytes[0]) << 24 | UInt32(seedersBytes[1]) << 16 | UInt32(seedersBytes[2]) << 8 | UInt32(seedersBytes[3])
        
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

 
