import Foundation
import Logging

/// DHT (Distributed Hash Table) client for peer discovery
public class DHTClient {
    private let logger: Logger
    private let nodeId: Data
    private var routingTable: [String: DHTNode] = [:]
    private let port: UInt16
    private let udpSocket: UDPSocket
    private let queue = DispatchQueue(label: "dht.client", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    
    // Improved routing table with buckets
    private var buckets: [DHTBucket] = []
    private let maxBucketSize = 8
    private let maxBuckets = 160
    
    // Pending queries for better response handling
    private var pendingQueries: [String: DHTQuery] = [:]
    
    public init(port: UInt16 = 6881) {
        self.port = port
        self.nodeId = Data((0..<20).map { _ in UInt8.random(in: 0...255) })
        self.logger = Logger(label: "SwiftyBT.DHT")
        self.udpSocket = UDPSocket(timeout: 10.0)
        
        // Initialize buckets
        for _ in 0..<maxBuckets {
            buckets.append(DHTBucket(maxSize: maxBucketSize))
        }

        // Mark queue for reentrancy detection
        queue.setSpecific(key: queueKey, value: true)
    }
    
    /// Start DHT client
    public func start() async throws {
        logger.info("Starting DHT client on port \(port)")
        
        // Bootstrap with known DHT nodes
        try await bootstrap()
    }
    
    /// Stop DHT client
    public func stop() {
        // Cleanup any pending operations
        pendingQueries.removeAll()
    }
    
    /// Find peers for a torrent with improved algorithm
    /// - Parameter infoHash: Info hash of the torrent
    /// - Returns: Array of peer addresses
    public func findPeers(for infoHash: Data) async throws -> [String] {
        logger.info("Finding peers for info hash: \(infoHash.map { String(format: "%02x", $0) }.joined())")
        
        var peers: Set<String> = []
        let targetId = infoHash
        
        // Get closest nodes to target
        var nodesToQuery = getClosestNodes(to: targetId, limit: 8)
        var queriedNodes: Set<String> = []
        
        // Perform iterative lookup with multiple rounds
        for round in 0..<5 { // Increased rounds for better coverage
            logger.info("DHT lookup round \(round + 1)")
            
            var newNodesToQuery: [DHTNode] = []
            var roundPeers: Set<String> = []
            
            // Query nodes in parallel
            await withTaskGroup(of: (String, [String], [DHTNode]).self) { group in
                for node in nodesToQuery {
                    let nodeKey = "\(node.address):\(node.port)"
                    guard !queriedNodes.contains(nodeKey) else { continue }
                    
                    group.addTask {
                        do {
                            let response = try await self.getPeers(from: node, infoHash: infoHash)
                            return (nodeKey, response.peers, response.nodes)
                        } catch {
                            self.logger.warning("Failed to get peers from node \(node.address): \(error)")
                            return (nodeKey, [], [])
                        }
                    }
                }
                
                // Collect results
                for await (nodeKey, nodePeers, nodeNodes) in group {
                    queriedNodes.insert(nodeKey)
                    roundPeers.formUnion(nodePeers)
                    newNodesToQuery.append(contentsOf: nodeNodes)
                }
            }
            
            peers.formUnion(roundPeers)
            logger.info("Round \(round + 1): Found \(roundPeers.count) peers, \(newNodesToQuery.count) new nodes")
            
            // Update nodes to query for next round
            nodesToQuery = newNodesToQuery
                .filter { node in
                    let nodeKey = "\(node.address):\(node.port)"
                    return !queriedNodes.contains(nodeKey)
                }
                .sorted { node1, node2 in
                    let distance1 = xorDistance(node1.id, targetId)
                    let distance2 = xorDistance(node2.id, targetId)
                    return distance1.count > 0 && distance2.count > 0 && distance1[0] < distance2[0]
                }
                .prefix(8)
                .map { $0 }
            
            if nodesToQuery.isEmpty {
                logger.info("No more nodes to query")
                break
            }
        }
        
        logger.info("DHT search completed. Found \(peers.count) unique peers")
        return Array(peers)
    }
    
    /// Bootstrap with known DHT nodes
    private func bootstrap() async throws {
        let bootstrapNodes = [
            "router.bittorrent.com:6881",
            "dht.transmissionbt.com:6881",
            "router.utorrent.com:6881",
            "dht.aelitis.com:6881",
            "router.bitcomet.com:6881"
        ]
        
        logger.info("Bootstrapping DHT with \(bootstrapNodes.count) nodes")
        
        await withTaskGroup(of: Void.self) { group in
            for nodeAddress in bootstrapNodes {
                group.addTask {
                    do {
                        let components = nodeAddress.split(separator: ":")
                        guard components.count == 2 else {
                            return
                        }
                        
                        let host = String(components.first ?? "")
                        let portString = String(components.last ?? "")
                        guard let port = UInt16(portString) else {
                            return
                        }
                        
                        let node = DHTNode(
                            id: Data((0..<20).map { _ in UInt8.random(in: 0...255) }),
                            address: host,
                            port: port
                        )
                        
                        try await self.ping(node: node)
                        self.addNode(node)
                        self.logger.info("Successfully bootstrapped with \(nodeAddress)")
                        
                    } catch {
                        self.logger.warning("Failed to bootstrap with node \(nodeAddress): \(error)")
                    }
                }
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
    public func ping(node: DHTNode) async throws {
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
    
    /// Get peers from a DHT node with timeout
    private func getPeers(from node: DHTNode, infoHash: Data) async throws -> (peers: [String], nodes: [DHTNode]) {
        let query: [String: Any] = [
            "t": "gp",
            "y": "q",
            "q": "get_peers",
            "a": [
                "id": nodeId.base64EncodedString(),
                "info_hash": infoHash.base64EncodedString()
            ]
        ]
        
        // Send query with timeout
        return try await withThrowingTaskGroup(of: (peers: [String], nodes: [DHTNode]).self) { group in
            group.addTask {
                try await self.sendQuery(query, to: node)
                // For now, return empty results as we need to implement proper response handling
                return (peers: [], nodes: [])
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                throw DHTError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Send query to a DHT node
    private func sendQuery(_ query: [String: Any], to node: DHTNode) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: query) else {
            throw DHTError.encodingFailed
        }
        
        try await udpSocket.send(data, to: node.address, port: node.port)
    }
    
    /// Send response to a DHT node
    private func sendResponse(_ response: [String: Any], to message: [String: Any]) async throws {
        // Implementation would send response back to the sender
    }
    

    
    /// Get closest nodes to a target ID using improved algorithm
    private func getClosestNodes(to targetId: Data, limit: Int) -> [DHTNode] {
        // Take a snapshot of buckets under synchronization to avoid races
        let snapshotBuckets: [DHTBucket]
        if DispatchQueue.getSpecific(key: queueKey) == true {
            snapshotBuckets = self.buckets
        } else {
            snapshotBuckets = queue.sync { self.buckets }
        }

        // Use bucket-based routing for better performance
        let bucketIndex = getBucketIndex(for: targetId)
        var nodes: [DHTNode] = []

        // Get nodes from the target bucket
        if bucketIndex < snapshotBuckets.count {
            nodes.append(contentsOf: snapshotBuckets[bucketIndex].nodes)
        }

        // If not enough nodes, get from neighboring buckets
        if nodes.count < limit {
            let startIndex = max(0, bucketIndex - 1)
            let endIndex = min(snapshotBuckets.count - 1, bucketIndex + 1)

            for i in startIndex...endIndex {
                if i != bucketIndex {
                    nodes.append(contentsOf: snapshotBuckets[i].nodes)
                }
            }
        }

        // Sort by distance and return top nodes
        return nodes
            .sorted { node1, node2 in
                let distance1 = xorDistance(node1.id, targetId)
                let distance2 = xorDistance(node2.id, targetId)
                return distance1.count > 0 && distance2.count > 0 && distance1[0] < distance2[0]
            }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get bucket index for a node ID
    private func getBucketIndex(for nodeId: Data) -> Int {
        guard nodeId.count > 0 else { return 0 }
        
        // Find the first bit that differs from our node ID
        for i in 0..<min(nodeId.count, self.nodeId.count) {
            let xor = nodeId[i] ^ self.nodeId[i]
            if xor != 0 {
                // Find the highest bit set in the XOR
                for bit in 0..<8 {
                    if (xor & (1 << (7 - bit))) != 0 {
                        return i * 8 + bit
                    }
                }
            }
        }
        
        return 0
    }
    
    /// Add node to routing table using bucket system
    private func addNode(_ node: DHTNode) {
        // Serialize bucket and routing table updates to avoid data races
        queue.async {
            let bucketIndex = self.getBucketIndex(for: node.id)
            if bucketIndex < self.buckets.count {
                self.buckets[bucketIndex].addNode(node)
            }
            let key = "\(node.address):\(node.port)"
            self.routingTable[key] = node
        }
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

/// DHT bucket for improved routing
private struct DHTBucket {
    private(set) var nodes: [DHTNode] = []
    private let maxSize: Int
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    mutating func addNode(_ node: DHTNode) {
        // Remove existing node with same address
        nodes.removeAll { $0.address == node.address && $0.port == node.port }
        
        // Add new node
        nodes.append(node)
        
        // Keep only maxSize nodes
        if nodes.count > maxSize {
            nodes.removeFirst()
        }
    }
}

/// DHT query for tracking pending requests
private struct DHTQuery {
    let id: String
    let timestamp: Date
    let node: DHTNode
    let queryType: String
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
