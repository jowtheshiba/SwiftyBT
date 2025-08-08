import Foundation
import Network
import CryptoKit

@available(iOS 13.0, macOS 10.15, *)
class DHTTrackersProvider: @unchecked Sendable {
    
    private var udpSocket: NWConnection?
    private var isSearching = false
    private var foundTrackers: [TorrentURLTracker] = []
    private let queue = DispatchQueue(label: "DHTTrackersProvider", qos: .utility)
    private var transactionId: String = ""
    private var nodeId: String = ""
    private var activeConnections: [NWConnection] = []
    private var discoveredNodes: [String] = []
    private var searchStartTime: Date = Date()
    private var currentInfoHash: String = ""
    
    // MARK: - Public Methods
    
    /// Запускает поиск DHT трекеров для TorrentFile
    /// - Parameters:
    ///   - torrentFile: Файл торрента
    ///   - completion: Колбэк с найденными трекерами
    func searchTrackers(for torrentFile: TorrentFile, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let infoHash = getInfoHash(from: torrentFile)
        searchTrackers(infoHash: infoHash, completion: completion)
    }
    
    /// Запускает поиск DHT трекеров для MagnetLink
    /// - Parameters:
    ///   - magnetLink: Магнет-ссылка
    ///   - completion: Колбэк с найденными трекерами
    func searchTrackers(for magnetLink: MagnetLink, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let infoHash = magnetLink.infoHash
        searchTrackers(infoHash: infoHash, completion: completion)
    }
    
    /// Останавливает поиск трекеров
    func stopSearch() {
        isSearching = false
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()
        udpSocket?.cancel()
        udpSocket = nil
    }
    
    // MARK: - Private Methods
    
    private func searchTrackers(infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        guard !isSearching else { return }
        
        isSearching = true
        foundTrackers.removeAll()
        activeConnections.removeAll()
        discoveredNodes.removeAll()
        searchStartTime = Date()
        currentInfoHash = infoHash
        
        // Генерируем случайный transaction ID и node ID
        transactionId = generateRandomString(length: 2)
        nodeId = generateRandomString(length: 20)
        
        print("🔍 Starting DHT search for info_hash: \(infoHash)")
        
        queue.async { [weak self] in
            self?.startDHTBootstrap(infoHash: infoHash, completion: completion)
        }
    }
    
    private func startDHTBootstrap(infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        // Начинаем с bootstrap узлов
        let bootstrapNodes = DHTPredefinedNodes.getAllNodes()
        
        print("🌐 Connecting to \(bootstrapNodes.count) bootstrap DHT nodes...")
        for node in bootstrapNodes {
            print("   🔗 Connecting to: \(node)")
            connectToDHTNode(node: node, infoHash: infoHash, completion: completion)
        }
        
        // Таймаут для поиска
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.isSearching == true {
                print("⏰ DHT search timeout reached")
                self?.stopSearch()
                completion(self?.foundTrackers ?? [])
            }
        }
    }
    
    private func connectToDHTNode(node: String, infoHash: String, completion: @escaping @Sendable ([TorrentURLTracker]) -> Void) {
        let components = node.components(separatedBy: ":")
        guard components.count == 2,
              let host = components.first,
              let portString = components.last,
              let port = UInt16(portString) else {
            return
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let connection = NWConnection(to: endpoint, using: .udp)
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Сначала отправляем FIND_NODE для поиска ближайших узлов
                self?.sendDHTFindNodeQuery(connection: connection, targetNodeId: infoHash)
            case .failed(let error):
                break
            case .cancelled:
                break
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func sendDHTFindNodeQuery(connection: NWConnection, targetNodeId: String) {
        // Создаем DHT FIND_NODE запрос
        let query = createDHTFindNodeQuery(targetNodeId: targetNodeId)
        
        connection.send(content: query, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ Failed to send FIND_NODE query: \(error)")
            } else {
                self?.receiveDHTResponse(connection: connection)
            }
        })
    }
    
    private func sendDHTGetPeersQuery(connection: NWConnection, infoHash: String) {
        // Создаем DHT GET_PEERS запрос
        let query = createDHTGetPeersQuery(infoHash: infoHash)
        
        connection.send(content: query, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ Failed to send GET_PEERS query: \(error)")
            } else {
                self?.receiveDHTResponse(connection: connection)
            }
        })
    }
    
    private func receiveDHTResponse(connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            if let error = error {
                return
            }
            
            if let data = content {
                self?.processDHTResponse(data: data, connection: connection)
            }
            
            // Продолжаем слушать, если еще ищем
            if self?.isSearching == true {
                self?.receiveDHTResponse(connection: connection)
            }
        }
    }
    
    private func processDHTResponse(data: Data, connection: NWConnection) {
        // Парсим DHT ответ
        do {
            let response = try BEncode.decode(data)
            if let dict = response.dictValue {
                if let y = dict["y"]?.stringValue {
                    switch y {
                    case "r": // response
                        if let r = dict["r"]?.dictValue {
                            // Проверяем, есть ли узлы в ответе (FIND_NODE ответ)
                            if let nodes = r["nodes"]?.dataValue {
                                self.processDiscoveredNodes(nodes: nodes)
                            }
                            
                            // Проверяем, есть ли трекеры в ответе (GET_PEERS ответ)
                            if let values = r["values"]?.listValue {
                                print("🎯 Found \(values.count) trackers for your torrent!")
                                
                                for value in values {
                                    if let trackerData = value.dataValue,
                                       let trackerString = String(data: trackerData, encoding: .utf8) {
                                        let tracker = TorrentURLTracker(
                                            trackerURL: trackerString,
                                            trackerType: .udp
                                        )
                                        foundTrackers.append(tracker)
                                        print("✅ Found DHT tracker: \(trackerString)")
                                        print("   📌 This tracker is specifically for your torrent!")
                                        print("   🎯 Info Hash: \(currentInfoHash)")
                                        print("   📊 Total DHT trackers found so far: \(foundTrackers.count)")
                                    }
                                }
                            }
                            
                            // Проверяем, есть ли nodes в GET_PEERS ответе (когда нет трекеров)
                            if let nodes = r["nodes"]?.dataValue {
                                self.processDiscoveredNodes(nodes: nodes)
                            }
                        }
                    case "e": // error
                        if let e = dict["e"]?.listValue,
                           e.count >= 2,
                           let errorCode = e[0].intValue,
                           let errorMessage = e[1].stringValue {
                            print("❌ DHT error: \(errorCode) - \(errorMessage)")
                        }
                    default:
                        break
                    }
                }
            }
        } catch {
            // Игнорируем ошибки парсинга
        }
    }
    
    private func processDiscoveredNodes(nodes: Data) {
        // Парсим найденные узлы и подключаемся к ним
        let nodeSize = 26
        let nodeCount = nodes.count / nodeSize
        
        print("🔍 Processing \(nodeCount) discovered DHT nodes...")
        
        for i in 0..<nodeCount {
            let startIndex = i * nodeSize
            let endIndex = startIndex + nodeSize
            
            guard endIndex <= nodes.count else { break }
            
            let nodeData = nodes.subdata(in: startIndex..<endIndex)
            
            // Извлекаем компоненты узла (20 байт nodeId + 4 байта IP + 2 байта порт)
            let _ = nodeData.prefix(20) // nodeId - пока не используем
            let ipData = nodeData.dropFirst(20).prefix(4)
            let portData = nodeData.dropFirst(24).prefix(2)
            
            // Конвертируем IP
            let ipBytes = Array(ipData)
            guard ipBytes.count == 4 else { continue }
            let ipString = ipBytes.map { String($0) }.joined(separator: ".")
            
            // Конвертируем порт
            let portBytes = Array(portData)
            guard portBytes.count == 2 else { continue }
            let portValue = UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])
            
            let nodeAddress = "\(ipString):\(portValue)"
            
            if !discoveredNodes.contains(nodeAddress) {
                discoveredNodes.append(nodeAddress)
                print("   🔗 New DHT node discovered: \(nodeAddress)")
                
                // Подключаемся к новому узлу
                connectToDiscoveredNode(node: nodeAddress)
            }
        }
        
        print("📊 Total discovered nodes: \(discoveredNodes.count)")
    }
    
    private func connectToDiscoveredNode(node: String) {
        let components = node.components(separatedBy: ":")
        guard components.count == 2,
              let host = components.first,
              let portString = components.last,
              let port = UInt16(portString) else {
            return
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let connection = NWConnection(to: endpoint, using: .udp)
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Отправляем GET_PEERS запрос к найденному узлу с правильным info_hash
                if let currentInfoHash = self?.currentInfoHash {
                    self?.sendDHTGetPeersQuery(connection: connection, infoHash: currentInfoHash)
                }
            case .failed(let error):
                break
            case .cancelled:
                break
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func createDHTFindNodeQuery(targetNodeId: String) -> Data {
        // Создаем DHT FIND_NODE запрос в bencode формате
        var queryDict: [String: BEncodeValue] = [:]
        
        // Transaction ID
        queryDict["t"] = .bytes(transactionId.data(using: .utf8)!)
        
        // Query type
        queryDict["y"] = .bytes("q".data(using: .utf8)!)
        queryDict["q"] = .bytes("find_node".data(using: .utf8)!)
        
        // Arguments
        var args: [String: BEncodeValue] = [:]
        args["id"] = .bytes(nodeId.data(using: .utf8)!)
        args["target"] = .bytes(targetNodeId.data(using: .utf8)!)
        queryDict["a"] = .dict(args)
        
        let query = BEncode.encode(.dict(queryDict))
        return query
    }
    
    private func createDHTGetPeersQuery(infoHash: String) -> Data {
        // Создаем DHT GET_PEERS запрос в bencode формате
        var queryDict: [String: BEncodeValue] = [:]
        
        // Transaction ID
        queryDict["t"] = .bytes(transactionId.data(using: .utf8)!)
        
        // Query type
        queryDict["y"] = .bytes("q".data(using: .utf8)!)
        queryDict["q"] = .bytes("get_peers".data(using: .utf8)!)
        
        // Arguments
        var args: [String: BEncodeValue] = [:]
        args["id"] = .bytes(nodeId.data(using: .utf8)!)
        
        // Конвертируем info_hash из hex строки в байты
        let infoHashBytes = hexStringToBytes(infoHash)
        args["info_hash"] = .bytes(infoHashBytes)
        queryDict["a"] = .dict(args)
        
        let query = BEncode.encode(.dict(queryDict))
        return query
    }
    
    private func hexStringToBytes(_ hexString: String) -> Data {
        var data = Data()
        var index = hexString.startIndex
        
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let hexPair = String(hexString[index..<nextIndex])
            
            if let byte = UInt8(hexPair, radix: 16) {
                data.append(byte)
            }
            
            index = nextIndex
        }
        
        return data
    }
    
    private func getInfoHash(from torrentFile: TorrentFile) -> String {
        // Вычисляем SHA1 хеш от bencoded info секции
        let infoBEncode = torrentFile.info.toBEncodeValue()
        let infoData = BEncode.encode(infoBEncode)
        
        let hash = Insecure.SHA1.hash(data: infoData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func generateRandomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}
