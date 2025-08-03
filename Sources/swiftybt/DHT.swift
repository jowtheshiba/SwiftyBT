import Foundation
import Network
import Logging

/// DHT (Distributed Hash Table) client for peer discovery
public class DHTClient {
    private let logger: Logger
    private let nodeId: Data
    private var routingTable: [String: DHTNode] = [:]
    private let port: UInt16
    private var udpConnection: NWConnection?
    private let queue = DispatchQueue(label: "dht.client", qos: .utility)
    
    public init(port: UInt16 = 6881) {
        self.port = port
        self.nodeId = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        self.logger = Logger(label: "SwiftyBT.DHT")
    }
    
    /// Start DHT client
    public func start() async throws {
        logger.info("Starting DHT client on port \(port)")
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("0.0.0.0"),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        
        udpConnection = NWConnection(to: endpoint, using: .udp)
        
        udpConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("DHT UDP connection ready")
                Task {
                    await self?.startListening()
                }
            case .failed(let error):
                self?.logger.error("DHT UDP connection failed: \(error)")
            case .cancelled:
                self?.logger.info("DHT UDP connection cancelled")
            default:
                break
            }
        }
        
        udpConnection?.start(queue: queue)
        
        // Bootstrap with known DHT nodes
        try await bootstrap()
    }
    
    /// Stop DHT client
    public func stop() {
        udpConnection?.cancel()
        udpConnection = nil
    }
    
    /// Find peers for a torrent
    /// - Parameter infoHash: Info hash of the torrent
    /// - Returns: Array of peer addresses
    public func findPeers(for infoHash: Data) async throws -> [String] {
        logger.info("Finding peers for info hash: \(infoHash.map { String(format: "%02x", $0) }.joined())")
        
        var peers: Set<String> = []
        let targetId = infoHash
        
        // Perform iterative lookup
        var nodesToQuery = getClosestNodes(to: targetId, limit: 8)
        
        for _ in 0..<3 { // Max 3 iterations
            var newNodesToQuery: [DHTNode] = []
            
            for node in nodesToQuery {
                do {
                    let response = try await getPeers(from: node, infoHash: infoHash)
                    peers.formUnion(response.peers)
                    newNodesToQuery.append(contentsOf: response.nodes)
                } catch {
                    logger.warning("Failed to get peers from node \(node.address): \(error)")
                }
            }
            
            nodesToQuery = newNodesToQuery.prefix(8).map { $0 }
            
            if nodesToQuery.isEmpty {
                break
            }
        }
        
        return Array(peers)
    }
    
    /// Bootstrap with known DHT nodes
    private func bootstrap() async throws {
        let bootstrapNodes = [
            "router.bittorrent.com:6881",
            "dht.transmissionbt.com:6881",
            "router.utorrent.com:6881"
        ]
        
        for nodeAddress in bootstrapNodes {
            do {
                let components = nodeAddress.split(separator: ":")
                guard components.count == 2,
                      let host = components.first,
                      let portString = components.last,
                      let port = UInt16(portString) else {
                    continue
                }
                
                let node = DHTNode(
                    id: Data((0..<20).map { _ in UInt8.random(in: 0...255) }),
                    address: String(host),
                    port: port
                )
                
                try await ping(node: node)
                addNode(node)
                
            } catch {
                logger.warning("Failed to bootstrap with node \(nodeAddress): \(error)")
            }
        }
    }
    
    /// Start listening for incoming DHT messages
    private func startListening() async {
        guard let connection = udpConnection else { return }
        
        while true {
            do {
                let data = try await receiveData(from: connection)
                try await handleIncomingMessage(data)
            } catch {
                logger.error("Error receiving DHT message: \(error)")
            }
        }
    }
    
    /// Handle incoming DHT message
    private func handleIncomingMessage(_ data: Data) async throws {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let y = message["y"] as? String else {
            return
        }
        
        switch y {
        case "q": // Query
            try await handleQuery(message)
        case "r": // Response
            try await handleResponse(message)
        case "e": // Error
            try await handleError(message)
        default:
            break
        }
    }
    
    /// Handle DHT query message
    private func handleQuery(_ message: [String: Any]) async throws {
        guard let q = message["q"] as? String else { return }
        
        switch q {
        case "ping":
            try await handlePingQuery(message)
        case "find_node":
            try await handleFindNodeQuery(message)
        case "get_peers":
            try await handleGetPeersQuery(message)
        case "announce_peer":
            try await handleAnnouncePeerQuery(message)
        default:
            break
        }
    }
    
    /// Handle ping query
    private func handlePingQuery(_ message: [String: Any]) async throws {
        guard let a = message["a"] as? [String: Any],
              let id = a["id"] as? String,
              let _ = Data(base64Encoded: id) else {
            return
        }
        
        let response: [String: Any] = [
            "t": message["t"] ?? "",
            "y": "r",
            "r": [
                "id": nodeId.base64EncodedString()
            ]
        ]
        
        try await sendResponse(response, to: message)
    }
    
    /// Handle find_node query
    private func handleFindNodeQuery(_ message: [String: Any]) async throws {
        guard let a = message["a"] as? [String: Any],
              let target = a["target"] as? String,
              let targetData = Data(base64Encoded: target) else {
            return
        }
        
        let closestNodes = getClosestNodes(to: targetData, limit: 8)
        let nodes = closestNodes.map { node in
            node.id.base64EncodedString() + node.address + String(format: "%04d", node.port)
        }.joined()
        
        let response: [String: Any] = [
            "t": message["t"] ?? "",
            "y": "r",
            "r": [
                "id": nodeId.base64EncodedString(),
                "nodes": nodes
            ]
        ]
        
        try await sendResponse(response, to: message)
    }
    
    /// Handle get_peers query
    private func handleGetPeersQuery(_ message: [String: Any]) async throws {
        guard let a = message["a"] as? [String: Any],
              let infoHash = a["info_hash"] as? String,
              let infoHashData = Data(base64Encoded: infoHash) else {
            return
        }
        
        // For now, return closest nodes
        let closestNodes = getClosestNodes(to: infoHashData, limit: 8)
        let nodes = closestNodes.map { node in
            node.id.base64EncodedString() + node.address + String(format: "%04d", node.port)
        }.joined()
        
        let response: [String: Any] = [
            "t": message["t"] ?? "",
            "y": "r",
            "r": [
                "id": nodeId.base64EncodedString(),
                "nodes": nodes,
                "token": "token" // Simple token for now
            ]
        ]
        
        try await sendResponse(response, to: message)
    }
    
    /// Handle announce_peer query
    private func handleAnnouncePeerQuery(_ message: [String: Any]) async throws {
        // For now, just acknowledge the announce
        let response: [String: Any] = [
            "t": message["t"] ?? "",
            "y": "r",
            "r": [
                "id": nodeId.base64EncodedString()
            ]
        ]
        
        try await sendResponse(response, to: message)
    }
    
    /// Handle DHT response message
    private func handleResponse(_ message: [String: Any]) async throws {
        // Handle responses to our queries
        // This would be implemented based on pending queries
    }
    
    /// Handle DHT error message
    private func handleError(_ message: [String: Any]) async throws {
        logger.warning("DHT error: \(message)")
    }
    
    /// Send ping to a DHT node
    private func ping(node: DHTNode) async throws {
        let query: [String: Any] = [
            "t": "pn",
            "y": "q",
            "q": "ping",
            "a": [
                "id": nodeId.base64EncodedString()
            ]
        ]
        
        try await sendQuery(query, to: node)
    }
    
    /// Get peers from a DHT node
    private func getPeers(from node: DHTNode, infoHash: Data) async throws -> (peers: [String], nodes: [DHTNode]) {
        // This would send the query and wait for response
        // For now, return empty results
        return (peers: [], nodes: [])
    }
    
    /// Send query to a DHT node
    private func sendQuery(_ query: [String: Any], to node: DHTNode) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: query),
              let connection = udpConnection else {
            throw DHTError.encodingFailed
        }
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.logger.error("Failed to send DHT query: \(error)")
            }
        })
    }
    
    /// Send response to a DHT node
    private func sendResponse(_ response: [String: Any], to message: [String: Any]) async throws {
        // Implementation would send response back to the sender
    }
    
    /// Receive data from UDP connection
    private func receiveData(from connection: NWConnection) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: DHTError.receiveFailed)
                }
            }
        }
    }
    
    /// Get closest nodes to a target ID
    private func getClosestNodes(to targetId: Data, limit: Int) -> [DHTNode] {
        return Array(routingTable.values)
            .sorted { node1, node2 in
                let distance1 = xorDistance(node1.id, targetId)
                let distance2 = xorDistance(node2.id, targetId)
                // Compare distances as integers for sorting
                return distance1.count > 0 && distance2.count > 0 && distance1[0] < distance2[0]
            }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Add node to routing table
    private func addNode(_ node: DHTNode) {
        let key = "\(node.address):\(node.port)"
        routingTable[key] = node
    }
    
    /// Calculate XOR distance between two node IDs
    private func xorDistance(_ id1: Data, _ id2: Data) -> Data {
        guard id1.count == id2.count else { return Data() }
        
        var result = Data()
        for i in 0..<id1.count {
            result.append(id1[i] ^ id2[i])
        }
        return result
    }
}

/// DHT node representation
public struct DHTNode {
    public let id: Data
    public let address: String
    public let port: UInt16
    
    public init(id: Data, address: String, port: UInt16) {
        self.id = id
        self.address = address
        self.port = port
    }
}

/// DHT errors
public enum DHTError: Error {
    case encodingFailed
    case receiveFailed
    case invalidNode
    case timeout
} 