import Foundation
import Logging

/// PEX (Peer Exchange) client for exchanging peer lists
public class PEXClient {
    private let logger: Logger
    private var knownPeers: Set<String> = []
    private let maxPeersToSend = 50
    private let maxPeersToReceive = 100
    
    public init() {
        self.logger = Logger(label: "SwiftyBT.PEX")
    }
    
    /// Create PEX message for sending to peers
    /// - Parameter peers: List of peer addresses to share
    /// - Returns: PEX message data
    public func createPEXMessage(peers: [String]) -> Data? {
        let peerList = Array(peers.prefix(maxPeersToSend))
        
        // PEX message format: bencoded dictionary
        let message: [String: Bencode.Value] = [
            "added": .string(peerList.joined(separator: "")),
            "added.f": .string(String(repeating: "0", count: peerList.count)), // Flags: 0 = not interested
            "dropped": .string("")
        ]
        
        return Bencode.encode(.dictionary(message))
    }
    
    /// Parse PEX message from peer
    /// - Parameter data: Raw PEX message data
    /// - Returns: Parsed PEX message
    /// - Throws: PEXError if parsing fails
    public func parsePEXMessage(_ data: Data) throws -> PEXMessage {
        let value = try Bencode.parse(data)
        
        guard case .dictionary(let dict) = value else {
            throw PEXError.invalidMessageFormat
        }
        
        var added: [String] = []
        var addedFlags: [UInt8] = []
        var dropped: [String] = []
        
        // Parse added peers
        if let addedData = dict["added"],
           case .string(let addedString) = addedData {
            added = parsePeerList(addedString)
        }
        
        // Parse added flags
        if let addedFlagsData = dict["added.f"],
           case .string(let flagsString) = addedFlagsData {
            addedFlags = parseFlags(flagsString)
        }
        
        // Parse dropped peers
        if let droppedData = dict["dropped"],
           case .string(let droppedString) = droppedData {
            dropped = parsePeerList(droppedString)
        }
        
        return PEXMessage(
            added: added,
            addedFlags: addedFlags,
            dropped: dropped
        )
    }
    
    /// Parse peer list from string
    /// - Parameter peerString: String containing peer addresses
    /// - Returns: Array of peer addresses
    private func parsePeerList(_ peerString: String) -> [String] {
        var peers: [String] = []
        let bytes = Array(peerString.utf8)
        
        // Each peer is 6 bytes: 4 bytes IP + 2 bytes port
        let peerSize = 6
        let peerCount = bytes.count / peerSize
        
        for i in 0..<peerCount {
            let startIndex = i * peerSize
            guard startIndex + peerSize <= bytes.count else { break }
            
            let peerBytes = Array(bytes[startIndex..<startIndex + peerSize])
            
            // Extract IP address (first 4 bytes)
            let ipBytes = Array(peerBytes[0..<4])
            let ip = ipBytes.map { String($0) }.joined(separator: ".")
            
            // Extract port (last 2 bytes, big endian)
            let portBytes = Array(peerBytes[4..<6])
            let port = (UInt16(portBytes[0]) << 8) | UInt16(portBytes[1])
            
            let peerAddress = "\(ip):\(port)"
            peers.append(peerAddress)
        }
        
        return peers
    }
    
    /// Parse flags from string
    /// - Parameter flagsString: String containing flags
    /// - Returns: Array of flags
    private func parseFlags(_ flagsString: String) -> [UInt8] {
        return Array(flagsString.utf8)
    }
    
    /// Convert peer addresses to binary format
    /// - Parameter peers: Array of peer addresses
    /// - Returns: Binary data for PEX message
    private func peersToBinary(_ peers: [String]) -> Data {
        var data = Data()
        
        for peer in peers {
            let components = peer.split(separator: ":")
            guard components.count == 2,
                  let port = UInt16(components[1]) else {
                continue
            }
            
            let ipComponents = components[0].split(separator: ".")
            guard ipComponents.count == 4 else { continue }
            
            var ipBytes: [UInt8] = []
            for component in ipComponents {
                guard let byte = UInt8(component) else { continue }
                ipBytes.append(byte)
            }
            
            guard ipBytes.count == 4 else { continue }
            
            // Add IP bytes
            data.append(contentsOf: ipBytes)
            
            // Add port bytes (big endian)
            data.append(UInt8((port >> 8) & 0xFF))
            data.append(UInt8(port & 0xFF))
        }
        
        return data
    }
    
    /// Add peers to known list
    /// - Parameter peers: Array of peer addresses
    public func addKnownPeers(_ peers: [String]) {
        knownPeers.formUnion(peers)
    }
    
    /// Remove peers from known list
    /// - Parameter peers: Array of peer addresses
    public func removeKnownPeers(_ peers: [String]) {
        knownPeers.subtract(peers)
    }
    
    /// Get known peers
    /// - Returns: Array of known peer addresses
    public func getKnownPeers() -> [String] {
        return Array(knownPeers)
    }
    
    /// Create PEX message with current known peers
    /// - Returns: PEX message data
    public func createCurrentPEXMessage() -> Data? {
        let peers = Array(knownPeers.prefix(maxPeersToSend))
        return createPEXMessage(peers: peers)
    }
    
    /// Process PEX message and update known peers
    /// - Parameter message: Parsed PEX message
    public func processPEXMessage(_ message: PEXMessage) {
        // Add new peers
        addKnownPeers(message.added)
        
        // Remove dropped peers
        removeKnownPeers(message.dropped)
        
        logger.info("PEX: Added \(message.added.count) peers, dropped \(message.dropped.count) peers")
    }
    
    /// Check if peer supports PEX
    /// - Parameter peerId: Peer ID
    /// - Returns: True if peer supports PEX
    public func supportsPEX(peerId: Data) -> Bool {
        // Check if peer ID indicates PEX support
        // This is a simplified check - in practice, you'd check the peer's capabilities
        return true
    }
    
    /// Get PEX extension ID
    /// - Returns: Extension ID for PEX
    public func getExtensionID() -> UInt8 {
        return 1 // Standard PEX extension ID
    }
    
    /// Create PEX handshake message
    /// - Returns: PEX handshake data
    public func createHandshake() -> Data? {
        let handshake: [String: Bencode.Value] = [
            "m": .dictionary([
                "ut_pex": .integer(Int64(getExtensionID()))
            ])
        ]
        
        return Bencode.encode(.dictionary(handshake))
    }
    
    /// Parse PEX handshake message
    /// - Parameter data: Handshake data
    /// - Returns: True if peer supports PEX
    public func parseHandshake(_ data: Data) -> Bool {
        do {
            let value = try Bencode.parse(data)
            
            guard case .dictionary(let dict) = value,
                  let m = dict["m"],
                  case .dictionary(let extensions) = m,
                  let _ = extensions["ut_pex"] else {
                return false
            }
            
            // Check if peer supports PEX
            return true
            
        } catch {
            logger.warning("Failed to parse PEX handshake: \(error)")
            return false
        }
    }
}

/// PEX message structure
public struct PEXMessage {
    public let added: [String]
    public let addedFlags: [UInt8]
    public let dropped: [String]
    
    public init(added: [String], addedFlags: [UInt8], dropped: [String]) {
        self.added = added
        self.addedFlags = addedFlags
        self.dropped = dropped
    }
}

/// PEX errors
public enum PEXError: Error {
    case invalidMessageFormat
    case invalidPeerFormat
    case encodingFailed
    case decodingFailed
} 